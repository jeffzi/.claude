#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                    Git Safety Hook                         │
# ╰────────────────────────────────────────────────────────────╯
# Prevents committing plan files, auto-pushing, and destructive operations

# Check dependencies
command -v jq >/dev/null || {
	printf "Error: jq is required\n" >&2
	exit 1
}

input=$(cat)
full_command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Exit if no command found
[[ -z "$full_command" ]] && exit 0

# Skip if not in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# ╭────────────────────────────────────────────────────────────╮
# │                  Git Command Parsing                       │
# ╰────────────────────────────────────────────────────────────╯

# Extract git subcommand, handling global options like -C path
# Usage: subcmd=$(get_git_subcmd "$command")
get_git_subcmd() {
	local cmd="$1"
	local in_git=false
	local skip_next=false

	for word in $cmd; do
		if $skip_next; then
			skip_next=false
			continue
		fi

		# Wait for 'git'
		if ! $in_git; then
			[[ "$word" == "git" ]] && in_git=true
			continue
		fi

		# Handle options that take a separate argument
		case "$word" in
		-C | -c | --git-dir | --work-tree | --namespace)
			skip_next=true
			continue
			;;
		-C* | -c*)
			# -C and -c can have value attached (-Cpath)
			continue
			;;
		--*=* | -*)
			# Long option with value or other short option
			continue
			;;
		*)
			# First non-option word is the subcommand
			printf '%s' "$word"
			return 0
			;;
		esac
	done
	return 1
}

# Check if command is a git command with specific subcommand
# Uses global $command variable (set per sub-command in the main loop)
is_git_subcmd() {
	local expected="$1"
	local actual
	actual=$(get_git_subcmd "$command") || return 1
	[[ "$actual" == "$expected" ]]
}

# ╭────────────────────────────────────────────────────────────╮
# │                  Plan File Protection                      │
# ╰────────────────────────────────────────────────────────────╯

PLAN_PATTERNS_GREP=('\.claude/plans/' 'docs/plans/')

check_plan_files() {
	local files="$1"
	[[ -z "$files" ]] && return 0
	for pattern in "${PLAN_PATTERNS_GREP[@]}"; do
		printf '%s' "$files" | grep -q "$pattern" || continue
		printf "Error: Cannot stage/commit plan files matching '%s'. These are temporary analysis files.\n" "$pattern" >&2
		return 1
	done
}

# ╭────────────────────────────────────────────────────────────╮
# │           Destructive Operations Protection                │
# ╰────────────────────────────────────────────────────────────╯

block_destructive() {
	local operation="$1"
	local reason="$2"
	printf "BLOCKED: %s — %s\n" "$operation" "$reason" >&2
	exit 2
}

check_destructive_operations() {
	# ── Universal flags ──────────────────────────────────────────
	# --no-verify on any git command (skips pre-commit / pre-push hooks)
	[[ "$command" =~ --no-verify ]] &&
		block_destructive "git --no-verify" "Skipping hooks is forbidden."

	# ── Checkout / Switch ────────────────────────────────────────
	# git checkout -- <path> or checkout . (discard changes)
	is_git_subcmd "checkout" && [[ "$command" =~ [[:space:]](--([[:space:]]|$)|\.([[:space:]]|$)) ]] &&
		block_destructive "git checkout (discard)" "Discards uncommitted changes permanently."

	# git checkout -f / --force (force-switch discards uncommitted changes)
	is_git_subcmd "checkout" && [[ "$command" =~ [[:space:]](-f|--force)([[:space:]]|$) ]] &&
		block_destructive "git checkout --force" "Force-checkout discards uncommitted changes."

	# git switch -f / --force / --discard-changes
	is_git_subcmd "switch" && [[ "$command" =~ [[:space:]](-f|--force|--discard-changes)([[:space:]]|$) ]] &&
		block_destructive "git switch --force" "Force-switch discards uncommitted changes."

	# ── Reset / Clean / Stash ────────────────────────────────────
	# git reset (all forms — even soft/mixed reset can move HEAD or unstage unexpectedly)
	is_git_subcmd "reset" &&
		block_destructive "git reset" "Resets HEAD, staging area, or working tree. Use git restore --staged to unstage."

	# git clean -f
	is_git_subcmd "clean" && [[ "$command" =~ -[fdxn]*f ]] &&
		block_destructive "git clean -f" "Permanently deletes untracked files."

	# git stash (all forms — stash then lose is a common failure mode)
	is_git_subcmd "stash" &&
		block_destructive "git stash" "Stashing risks losing uncommitted work."

	# ── Branch ───────────────────────────────────────────────────
	# git branch -D
	is_git_subcmd "branch" && [[ "$command" =~ [[:space:]]-D ]] &&
		block_destructive "git branch -D" "Force-deletes branch, may lose unmerged commits."

	# ── Restore ──────────────────────────────────────────────────
	# git restore without --staged discards changes
	is_git_subcmd "restore" && [[ ! "$command" =~ --staged ]] &&
		block_destructive "git restore (discard)" "Discards uncommitted changes to files."

	# ── Commit ───────────────────────────────────────────────────
	# git commit --amend rewrites history
	is_git_subcmd "commit" && [[ "$command" =~ --amend ]] &&
		block_destructive "git commit --amend" "Rewrites the previous commit. Use with caution on shared branches."

	# ── History extraction with redirect (overwrite working tree) ─
	# git show / cat-file with stdout redirect (> but not 2>)
	if is_git_subcmd "show" || is_git_subcmd "cat-file"; then
		# Strip fd-specific redirects (2>, 3>, etc.) then check if > remains
		local _stripped
		_stripped=$(printf '%s' "$command" | sed 's/[0-9]>//g')
		[[ "$_stripped" =~ \> ]] &&
			block_destructive "git show/cat-file with redirect" \
				"Writing git history content to files can overwrite working tree changes."
	fi

	# ── Patch reversal ───────────────────────────────────────────
	# git apply -R / --reverse (undo applied patches)
	is_git_subcmd "apply" && [[ "$command" =~ [[:space:]](-R|--reverse)([[:space:]]|$) ]] &&
		block_destructive "git apply --reverse" "Reverse-applying patches can discard changes."

	# ── Rebase ───────────────────────────────────────────────────
	# git rebase with uncommitted changes
	if is_git_subcmd "rebase"; then
		git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && return 0
		block_destructive "git rebase (dirty)" "Rebasing with uncommitted changes risks losing work."
	fi
}

# ╭────────────────────────────────────────────────────────────╮
# │                    Command Checking                        │
# ╰────────────────────────────────────────────────────────────╯

# Check a single (sub-)command against all safety rules.
# Sets global $command so is_git_subcmd and regex checks work.
check_single_command() {
	command="$1"

	# Block push operations
	if is_git_subcmd "push"; then
		printf "Error: Automatic git push is not allowed. Review and push manually.\n" >&2
		exit 2
	fi

	# Block git add with explicit plan file paths
	if is_git_subcmd "add"; then
		for pattern in "${PLAN_PATTERNS_GREP[@]}"; do
			if printf '%s' "$command" | grep -q "$pattern"; then
				printf "Error: Cannot stage plan files matching '%s'. These are temporary analysis files.\n" "$pattern" >&2
				exit 2
			fi
		done

		# Block broad adds (git add ., git add -A, git add -a, git add --all) if plan files would be included
		if [[ "$command" =~ [[:space:]](\.|-[aA]|--all)([[:space:]]|$) ]]; then
			local root
			root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
			local pending_files
			pending_files=$(git -C "$root" ls-files --others --modified --exclude-standard 2>/dev/null)
			check_plan_files "$pending_files" || exit 2
		fi

		# Block force-add with broad scope (bypasses all gitignore rules)
		if [[ "$command" =~ [[:space:]](-f|--force)([[:space:]]|$) ]] &&
			[[ "$command" =~ [[:space:]](\.|-[aA]|--all)([[:space:]]|$) ]]; then
			block_destructive "git add --force (broad)" \
				"Force-adding with broad scope bypasses gitignore and may track unwanted files."
		fi

		# Check explicitly named paths against gitignore (local + global + .git/info/exclude)
		local _found_add=false _past_dashdash=false
		local -a _add_paths=()
		for _word in $command; do
			if ! $_found_add; then
				[[ "$_word" == "add" ]] && _found_add=true
				continue
			fi
			if [[ "$_word" == "--" ]]; then
				_past_dashdash=true
				continue
			fi
			if $_past_dashdash; then
				_add_paths+=("$_word")
				continue
			fi
			case "$_word" in
			-* | .) continue ;; # skip flags and broad-scope dot
			*) _add_paths+=("$_word") ;;
			esac
		done
		for _path in "${_add_paths[@]}"; do
			if git check-ignore -q -- "$_path" 2>/dev/null; then
				block_destructive "git add (gitignored)" \
					"'$_path' matches a gitignore rule (local or global). Do not track ignored files."
			fi
		done
	fi

	# Block commits if plan files are already staged
	if is_git_subcmd "commit"; then
		# Remind to load write-commit skill
		printf "STOP: You MUST load Skill(write-commit) before committing. If you have not loaded it yet, abort and load it now.\n" >&2

		local root
		root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
		local staged_files
		staged_files=$(git -C "$root" diff --cached --name-only 2>/dev/null)
		check_plan_files "$staged_files" || exit 2
	fi

	# Block git worktree remove if the target worktree has uncommitted changes
	if is_git_subcmd "worktree" && [[ "$command" =~ [[:space:]]remove([[:space:]]|$) ]]; then
		# Extract worktree path: last non-flag argument after 'remove'
		local wt_path="" found_remove=false
		for word in $command; do
			if $found_remove && [[ "$word" != -* ]]; then
				wt_path="$word"
			fi
			[[ "$word" == "remove" ]] && found_remove=true
		done
		if [[ -n "$wt_path" && -d "$wt_path" ]]; then
			if ! git -C "$wt_path" diff --quiet 2>/dev/null ||
				! git -C "$wt_path" diff --cached --quiet 2>/dev/null ||
				[[ -n "$(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
				block_destructive "git worktree remove (dirty)" \
					"Worktree at '$wt_path' has uncommitted changes. Commit work before removing."
			fi
		fi
	fi

	# Check destructive operations
	check_destructive_operations
}

# Split chained commands (&&, ||, ;, |) and check each independently.
# This prevents bypasses like: git add . && git checkout -- .
# where only the first git subcommand would otherwise be checked.
# Order matters: || before | to avoid partial replacement.
while IFS= read -r subcmd; do
	# Trim leading/trailing whitespace
	subcmd="${subcmd#"${subcmd%%[![:space:]]*}"}"
	subcmd="${subcmd%"${subcmd##*[![:space:]]}"}"
	[[ -z "$subcmd" ]] && continue
	check_single_command "$subcmd"
done <<<"$(printf '%s' "$full_command" | awk '{gsub(/&&/,"\n"); gsub(/\|\|/,"\n"); gsub(/\|/,"\n"); gsub(/;/,"\n"); print}')"

exit 0
