#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                    Git Safety Hook                         │
# ╰────────────────────────────────────────────────────────────╯
# Prevents committing plan files, auto-pushing, and destructive operations

command -v jq >/dev/null || {
	printf "Error: jq is required\n" >&2
	exit 1
}

# The hook runs with cwd set to the repo it is guarding, so sourced scripts are
# resolved from the script's own location — never relative to cwd or $HOME.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# fix-ci policy, shared with the wrapper that fronts the loop's pushes.
# shellcheck source=SCRIPTDIR/../scripts/fix-ci-policy.sh
. "$HOOK_DIR/../scripts/fix-ci-policy.sh"

# git subcommand parsing, shared with hooks/git-lock-guard.sh.
# shellcheck source=SCRIPTDIR/../scripts/git-parse.sh
. "$HOOK_DIR/../scripts/git-parse.sh"

input=$(cat)
full_command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

[[ -z "$full_command" ]] && exit 0

git --no-optional-locks rev-parse --git-dir >/dev/null 2>&1 || exit 0

# ╭────────────────────────────────────────────────────────────╮
# │                  Git Command Parsing                       │
# ╰────────────────────────────────────────────────────────────╯

# Uses global $command (set per sub-command in the main loop)
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
# │                  TDD Cycle Commit Guard                    │
# ╰────────────────────────────────────────────────────────────╯

# While a tdd-cycle agent runs (marker created/removed by the agent per
# agents/tdd-cycle.md), commits and staging are forbidden — the orchestrator
# owns all commits.
check_tdd_cycle_marker() {
	local subcmd="$1" git_dir
	git_dir=$(git --no-optional-locks rev-parse --git-dir 2>/dev/null) || return 0
	[[ -f "$git_dir/tdd-cycle-active" ]] || return 0
	printf "BLOCKED: git %s — a tdd-cycle agent is running and the orchestrator owns all commits.\n" "$subcmd" >&2
	printf "If you ARE the tdd-cycle agent: do not commit or stage; write your report instead.\n" >&2
	printf "If no tdd-cycle agent is running (stale marker), remove '%s/tdd-cycle-active' and retry.\n" "$git_dir" >&2
	exit 2
}

# ╭────────────────────────────────────────────────────────────╮
# │                  fix-ci Marker Relaxation                  │
# ╰────────────────────────────────────────────────────────────╯

# While `$GIT_DIR/fix-ci-active` exists, a CI-fix loop is running on throwaway
# `fix-ci/*` branches whose plain commits get squash-merged back. Two relaxations
# follow from that shape:
#
#   - The loop only ever appends commits, so a plain push is allowed on any
#     branch. Which branch HEAD points at (or whether it points at one at all)
#     is irrelevant. Append-only is enforced here, not assumed: force in every
#     form, `--mirror`, and any deletion outside `fix-ci/*` stay blocked.
#   - A squash-merged branch has no ancestry in its target, so `git branch -d`
#     refuses it and `-D` is the only way to clean up the loop's own branches.
#
# Both relaxations are scoped to the repo that raised the marker: the effective
# git dir comes from the command's own `-C` / `--git-dir`, so a marker in one
# repo never relaxes a command aimed at another.
#
# The loop never rewrites remote history: force-push in every form (including
# --force-with-lease) and --no-verify stay blocked, so a local amend cannot
# reach the remote except as a rejected non-fast-forward push.
#
# The marker expires so an interrupted session cannot leave a repo relaxed
# forever. Outside the freshness window the marker counts as absent and gets
# swept; the window itself is defined in scripts/fix-ci-policy.sh, alongside the
# `fix-ci/*` namespace rule, and shared with the wrapper that fronts the loop's
# pushes.

# Git dir the command actually targets, honouring its global `-C` / `--git-dir`
# options. Falls back to the hook's cwd when the command names no repo.
# Uses global $command (set per sub-command in the main loop).
git_target_dir() {
	local -a repo_args=()
	local word in_git=false capture_next=false skip_next=false

	for word in $command; do
		if $capture_next; then
			repo_args+=("$word")
			capture_next=false
			continue
		fi
		if $skip_next; then
			skip_next=false
			continue
		fi

		# Wait for 'git'
		if ! $in_git; then
			[[ "$word" == "git" ]] && in_git=true
			continue
		fi

		case "$word" in
		-C | --git-dir)
			repo_args+=("$word")
			capture_next=true
			;;
		-C* | --git-dir=*)
			# Value attached, as in -Cpath or --git-dir=path
			repo_args+=("$word")
			;;
		-c | --work-tree | --namespace)
			skip_next=true
			;;
		--*=* | -*) ;;
		*)
			# First non-option word is the subcommand: no repo options left
			break
			;;
		esac
	done

	git --no-optional-locks ${repo_args[@]+"${repo_args[@]}"} rev-parse --absolute-git-dir 2>/dev/null
}

# Uses global $command (set per sub-command in the main loop).
fix_ci_active() {
	local git_dir marker
	git_dir=$(git_target_dir) || return 1
	[[ -n "$git_dir" ]] || return 1
	marker="$git_dir/fix-ci-active"
	[[ -f "$marker" ]] || return 1

	if fix_ci_marker_fresh "$marker"; then
		return 0
	fi
	rm -f "$marker" 2>/dev/null || true
	return 1
}

# True when the push deletes nothing, or deletes only `fix-ci/*` refs — the
# same namespace rule local branch deletion follows. `--delete` / `-d` deletes
# every refspec it is given; without it, a leading-colon refspec such as
# ':main' deletes on its own.
# Uses global $command (set per sub-command in the main loop).
fix_ci_push_deletes_only_own() {
	local -a refs=()
	local word ref seen_push=false seen_remote=false delete_mode=false

	for word in $command; do
		if ! $seen_push; then
			[[ "$word" == "push" ]] && seen_push=true
			continue
		fi
		case "$word" in
		--delete | -d)
			delete_mode=true
			continue
			;;
		-*) continue ;;
		esac
		# The first bare word is the remote; the rest are refspecs.
		if ! $seen_remote; then
			seen_remote=true
			continue
		fi
		refs+=("$word")
	done

	if $delete_mode; then
		# Deleting without naming a ref: nothing proves it stays in namespace.
		[[ ${#refs[@]} -gt 0 ]] || return 1
	fi

	while IFS= read -r ref; do
		fix_ci_ref_in_namespace "$ref" || return 1
	done < <(fix_ci_deleted_refs "$delete_mode" ${refs[@]+"${refs[@]}"})
	return 0
}

# Set by fix_ci_allows_push when the marker is up but the push form is banned.
fix_ci_push_denial_op=""
fix_ci_push_denial_reason=""

# Uses global $command (set per sub-command in the main loop).
fix_ci_allows_push() {
	fix_ci_push_denial_op=""
	fix_ci_push_denial_reason=""
	fix_ci_active || return 1

	# Force in any long form: --force, --force-with-lease, --force-if-includes.
	# Short-option cluster containing f: -f, -fu, -uf. The [[:alnum:]]* run
	# never crosses a second dash, so long options and words such as
	# 'feature/fix-flaky' cannot match.
	# Force refspec: a token starting with '+', as in 'origin +main:main'.
	if [[ "$command" =~ [[:space:]]--force ]] ||
		[[ "$command" =~ [[:space:]]-[[:alnum:]]*f ]] ||
		[[ "$command" =~ [[:space:]][+][^[:space:]] ]]; then
		fix_ci_push_denial_op="git push --force"
		fix_ci_push_denial_reason="The fix-ci loop squash-merges; it never rewrites history."
		return 1
	fi

	# --mirror deletes every remote ref that has no local counterpart, so it is
	# never in namespace no matter what the refspecs say.
	if [[ "$command" =~ [[:space:]]--mirror([[:space:]]|$) ]] || ! fix_ci_push_deletes_only_own; then
		fix_ci_push_denial_op="git push (delete)"
		fix_ci_push_denial_reason="The fix-ci loop deletes only its own fix-ci/* branches, never other history."
		return 1
	fi

	return 0
}

# Uses global $command (set per sub-command in the main loop). True only when
# every branch named for deletion belongs to the loop's own `fix-ci/*` namespace.
fix_ci_allows_branch_delete() {
	fix_ci_active || return 1

	local -a names=()
	local word seen_branch=false
	for word in $command; do
		if ! $seen_branch; then
			[[ "$word" == "branch" ]] && seen_branch=true
			continue
		fi
		[[ "$word" == -* ]] && continue
		names+=("$word")
	done

	[[ ${#names[@]} -gt 0 ]] || return 1
	for word in "${names[@]}"; do
		fix_ci_ref_in_namespace "$word" || return 1
	done
	return 0
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
	# git checkout is banned entirely — use git switch (branches) or git restore --staged (unstage)
	is_git_subcmd "checkout" &&
		block_destructive "git checkout" "Banned. Use 'git switch' for branches, 'git restore --staged' for unstaging."

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
	is_git_subcmd "branch" && [[ "$command" =~ [[:space:]]-D ]] && ! fix_ci_allows_branch_delete &&
		block_destructive "git branch -D" "Force-deletes branch, may lose unmerged commits."

	# ── Restore ──────────────────────────────────────────────────
	if is_git_subcmd "restore"; then
		# --worktree / -W discards working tree changes even when combined with --staged
		[[ "$command" =~ [[:space:]](-W|--worktree)([[:space:]]|$) ]] &&
			block_destructive "git restore --worktree" "Discards uncommitted changes to files."

		# Without --staged, restore discards working-tree changes
		[[ ! "$command" =~ --staged ]] &&
			block_destructive "git restore (discard)" "Discards uncommitted changes to files."
	fi

	# ── Rm ───────────────────────────────────────────────────────
	# git rm deletes files from the working tree unless --cached or dry-run (-n/--dry-run)
	if is_git_subcmd "rm"; then
		[[ "$command" =~ [[:space:]]--cached([[:space:]]|$) ]] && return 0
		[[ "$command" =~ [[:space:]]--dry-run([[:space:]]|$) ]] && return 0
		# Bundled short flags containing n (dry-run): -n, -rn, -fn, etc.
		[[ "$command" =~ [[:space:]]-[a-zA-Z]*n ]] && return 0
		block_destructive "git rm" "Deletes files from the working tree. Use --cached to only unstage."
	fi

	# ── Reflog / prune ──────────────────────────────────────────
	# git reflog expire/delete
	is_git_subcmd "reflog" && [[ "$command" =~ [[:space:]](expire|delete)([[:space:]]|$) ]] &&
		block_destructive "git reflog expire/delete" "Destroys reflog entries, making recovery impossible."

	# git prune
	is_git_subcmd "prune" &&
		block_destructive "git prune" "Removes unreachable objects. Let git gc handle pruning safely."

	# git gc --prune=
	is_git_subcmd "gc" && [[ "$command" =~ [[:space:]]--prune= ]] &&
		block_destructive "git gc --prune" "Immediate pruning risks losing recoverable objects."

	# ── Commit ───────────────────────────────────────────────────

	# ── History extraction with redirect (overwrite working tree) ─
	# git show / cat-file with stdout redirect (> but not 2>)
	if is_git_subcmd "show" || is_git_subcmd "cat-file"; then
		# Strip fd-specific redirects (2>, 3>, etc.) then check if > remains
		local _stripped
		_stripped=$(printf '%s' "$command" | sed 's/[2-9]>//g')
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
		git --no-optional-locks diff --quiet 2>/dev/null && git --no-optional-locks diff --cached --quiet 2>/dev/null && return 0
		block_destructive "git rebase (dirty)" "Rebasing with uncommitted changes risks losing work."
	fi
}

# ╭────────────────────────────────────────────────────────────╮
# │                    Command Checking                        │
# ╰────────────────────────────────────────────────────────────╯

check_add_safety() {
	for pattern in "${PLAN_PATTERNS_GREP[@]}"; do
		if printf '%s' "$command" | grep -q "$pattern"; then
			printf "Error: Cannot stage plan files matching '%s'. These are temporary analysis files.\n" "$pattern" >&2
			exit 2
		fi
	done

	if [[ "$command" =~ [[:space:]](\.|-[aA]|--all)([[:space:]]|$) ]]; then
		local root
		root=$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null) || return 0
		local pending_files
		pending_files=$(git --no-optional-locks -C "$root" ls-files --others --modified --exclude-standard 2>/dev/null)
		check_plan_files "$pending_files" || exit 2
	fi

	# Block all force-adds — -f/--force bypasses gitignore, the only
	# reason to use it is to track ignored files, which is forbidden.
	if [[ "$command" =~ [[:space:]](-f|--force)([[:space:]]|$) ]]; then
		block_destructive "git add --force" \
			"Force-adding bypasses gitignore rules. Never track ignored files."
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
	for _path in ${_add_paths[@]+"${_add_paths[@]}"}; do
		if git --no-optional-locks check-ignore -q -- "$_path" 2>/dev/null; then
			block_destructive "git add (gitignored)" \
				"'$_path' matches a gitignore rule (local or global). Do not track ignored files."
		fi
	done
}

# Check a single (sub-)command against all safety rules.
# Sets global $command so is_git_subcmd and regex checks work.
check_single_command() {
	command="$1"

	# Block staging and commits while a tdd-cycle agent is running
	if is_git_subcmd "add" || is_git_subcmd "commit"; then
		check_tdd_cycle_marker "$(get_git_subcmd "$command")"
	fi

	if is_git_subcmd "push" && ! fix_ci_allows_push; then
		[[ -n "$fix_ci_push_denial_reason" ]] &&
			block_destructive "$fix_ci_push_denial_op" "$fix_ci_push_denial_reason"
		printf "Error: Automatic git push is not allowed. Review and push manually.\n" >&2
		exit 2
	fi

	if is_git_subcmd "add"; then
		check_add_safety
	fi

	if is_git_subcmd "commit"; then
		# Remind to load write-commit skill
		printf "STOP: You MUST load Skill(write-commit) before committing. If you have not loaded it yet, abort and load it now.\n" >&2

		local root
		root=$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null) || return 0
		local staged_files
		staged_files=$(git --no-optional-locks -C "$root" diff --cached --name-only 2>/dev/null)
		check_plan_files "$staged_files" || exit 2
	fi

	if is_git_subcmd "worktree" && [[ "$command" =~ [[:space:]]remove([[:space:]]|$) ]]; then
		# --force exists to override git's own refusal to remove a dirty worktree,
		# so it is banned outright like `git branch -D`, whatever the path is.
		# The [[:alnum:]]* run never crosses a second dash, so long options and
		# path-like words cannot false-match the short-option cluster check.
		if [[ "$command" =~ [[:space:]]--force([[:space:]]|$) ]] ||
			[[ "$command" =~ [[:space:]]-[[:alnum:]]*f ]]; then
			block_destructive "git worktree remove --force" \
				"Force-removal deletes a worktree that still holds uncommitted work."
		fi

		# Extract worktree path: last non-flag argument after 'remove'
		local wt_path="" found_remove=false word
		for word in $command; do
			if $found_remove && [[ "$word" != -* ]]; then
				wt_path="$word"
			fi
			[[ "$word" == "remove" ]] && found_remove=true
		done

		# A missing path, a path that arrived quoted (collapsed to the
		# placeholder, as in a loop over "$wt"), or one that does not resolve
		# all leave the worktree unverifiable — fail closed rather than wave
		# the removal through.
		if [[ -z "$wt_path" || "$wt_path" == "$QUOTED_PLACEHOLDER" || ! -d "$wt_path" ]]; then
			block_destructive "git worktree remove (unverifiable path)" \
				"The guard cannot confirm the worktree is clean. Re-run with a literal, unquoted path."
		fi

		if ! git --no-optional-locks -C "$wt_path" diff --quiet 2>/dev/null ||
			! git --no-optional-locks -C "$wt_path" diff --cached --quiet 2>/dev/null ||
			[[ -n "$(git --no-optional-locks -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
			block_destructive "git worktree remove (dirty)" \
				"Worktree at '$wt_path' has uncommitted changes. Commit work before removing."
		fi
	fi

	check_destructive_operations
}

# Split chained commands (&&, ||, ;, |) and check each fragment independently.
# This prevents bypasses like `git add . && git checkout -- .`, where only the
# first git subcommand would otherwise be checked.
#
# Quoted text is data, not commands: backslash escapes and quoted regions are
# neutralized before splitting, so a commit message that merely names a banned
# command is not an invocation. A double-quoted region is opaque all the way to
# its closing quote, heredocs nested in `-m "$(cat <<'EOF' …)"` included.
# Trade-off, accepted for simplicity: arguments inside quotes escape the path
# and flag checks.
#
# A quoted region collapses to a placeholder word rather than to whitespace:
# erasing it would vacate the value slot of a preceding option, letting the next
# word be consumed as that value. `git -C "$wt" checkout .` would then parse as
# subcommand '.' and walk straight past the checkout ban.
#
# The placeholder must never look like a git subcommand, an option, a redirect,
# or a path, so that occupying a slot cannot itself trigger a rule.
readonly QUOTED_PLACEHOLDER=__QUOTED__

sanitized=$(printf '%s' "$full_command" | awk -v q="'" -v ph="$QUOTED_PLACEHOLDER" '
	{ buf = buf $0 "\n" }
	END {
		gsub(/\\./, " ", buf)
		gsub(/"[^"]*"/, ph, buf)
		gsub(q "[^" q "]*" q, ph, buf)
		gsub(/&&|\|\||[|;]/, "\n", buf)
		printf "%s", buf
	}')

while IFS= read -r fragment; do
	fragment="${fragment#"${fragment%%[![:space:]]*}"}"
	fragment="${fragment%"${fragment##*[![:space:]]}"}"
	[[ -z "$fragment" ]] && continue
	check_single_command "$fragment"
done <<<"$sanitized"

exit 0
