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

# The hook's cwd may be any directory, so sourced scripts are resolved from the
# script's own location — never relative to cwd or $HOME.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# fix-ci policy, shared with the wrapper that fronts the loop's pushes.
# shellcheck source=SCRIPTDIR/../scripts/branch-policy.sh
. "$HOOK_DIR/../scripts/branch-policy.sh"

# git subcommand parsing, shared with hooks/git-lock-guard.sh.
# shellcheck source=SCRIPTDIR/../scripts/git-parse.sh
. "$HOOK_DIR/../scripts/git-parse.sh"

input=$(cat)
full_command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

[[ -z "$full_command" ]] && exit 0

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

# Prints the git dir the current $command targets; fails when it does not
# resolve. Shared by fix_ci_active, main_is_protected, and release_active.
# Uses global $command, set by whichever caller is active — a sub-command in
# the main loop, or a fragment in check_release_invocation.
current_target_git_dir() {
	local git_dir
	git_dir=$(git_target_dir "$command") || return 1
	[[ -n "$git_dir" ]] || return 1
	printf '%s' "$git_dir"
}

# ╭────────────────────────────────────────────────────────────╮
# │                  Plan File Protection                      │
# ╰────────────────────────────────────────────────────────────╯

PLAN_PATTERNS_GREP=('\.claude/plans/' 'docs/plans/')

# Returns (via stdout) the first PLAN_PATTERNS_GREP entry found in $1, or fails
# when none match. Shared by check_plan_files (a file list) and check_add_safety
# (the raw command text).
find_plan_pattern() {
	local text="$1" pattern
	for pattern in "${PLAN_PATTERNS_GREP[@]}"; do
		if printf '%s' "$text" | grep -q "$pattern"; then
			printf '%s' "$pattern"
			return 0
		fi
	done
	return 1
}

check_plan_files() {
	local files="$1" pattern
	[[ -z "$files" ]] && return 0
	pattern=$(find_plan_pattern "$files") || return 0
	printf "Error: Cannot stage/commit plan files matching '%s'. These are temporary analysis files.\n" "$pattern" >&2
	return 1
}

# ╭────────────────────────────────────────────────────────────╮
# │                  TDD Cycle Commit Guard                    │
# ╰────────────────────────────────────────────────────────────╯

# While a tdd-cycle agent runs (marker created/removed by the agent per
# agents/tdd-cycle.md), commits and staging are forbidden — the orchestrator
# owns all commits. The marker is read from the repo the command targets.
# Uses global $command (set per sub-command in the main loop).
check_tdd_cycle_marker() {
	local subcmd="$1" git_dir
	git_dir=$(git_target_dir "$command") || return 0
	[[ -f "$git_dir/tdd-cycle-active" ]] || return 0
	printf "BLOCKED: git %s — a tdd-cycle agent is running and the orchestrator owns all commits.\n" "$subcmd" >&2
	printf "If you ARE the tdd-cycle agent: do not commit or stage; write your report instead.\n" >&2
	printf "If no tdd-cycle agent is running (stale marker), remove '%s/tdd-cycle-active' and retry.\n" "$git_dir" >&2
	exit 2
}

# ╭────────────────────────────────────────────────────────────╮
# │                  fix-ci Marker Relaxation                  │
# ╰────────────────────────────────────────────────────────────╯

# While `$GIT_DIR/fix-ci-active` exists, the marker sanctions branch work the
# assistant drives itself: a fix-ci loop on throwaway `fix-ci/*` branches, and an
# execute-plan run shipping its `plan/*` branch to CI. Both shapes are the same —
# plain commits on a branch that is squash-merged back and then deleted — so two
# relaxations follow:
#
#   - The loop only ever appends commits, so a plain push is allowed on any
#     branch. Which branch HEAD points at (or whether it points at one at all)
#     is irrelevant. Append-only is enforced here, not assumed: force in every
#     form, `--mirror`, and any deletion outside `fix-ci/*` and `plan/*` stay
#     blocked.
#   - A squash-merged branch has no ancestry in its target, so `git branch -d`
#     refuses it and `-D` is the only way to clean up those own branches.
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
# swept; the window itself is defined in scripts/branch-policy.sh, alongside the
# namespace rule, and shared with the wrapper that fronts both loops' pushes.

# Uses global $command (set per sub-command in the main loop).
fix_ci_active() {
	local git_dir marker status=0
	git_dir=$(current_target_git_dir) || return 1
	marker="$git_dir/$FIX_CI_MARKER"
	[[ -f "$marker" ]] || return 1

	marker_fresh "$marker" || status=$?
	((status == 0)) && return 0
	# A stat that cannot answer says nothing about the marker's age: fail closed
	# without sweeping a marker a live loop may still own.
	((status == SH_STAT_UNUSABLE)) && return 1
	rm -f "$marker" 2>/dev/null || true
	return 1
}

# True when the push deletes nothing, or deletes only refs in a sanctioned
# namespace — the same rule local branch deletion follows. `--delete` / `-d` deletes
# every refspec it is given; without it, a leading-colon refspec such as
# ':main' deletes on its own.
# Uses global $command (set per sub-command in the main loop).
fix_ci_push_deletes_only_own() {
	local -a refs=()
	local word ref seen_remote=false delete_mode=false

	git_parse_command "$command" || return 1
	for word in ${GIT_SUBCMD_ARGS[@]+"${GIT_SUBCMD_ARGS[@]}"}; do
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
		ref_in_own_namespace "$ref" || return 1
	done < <(push_deleted_refs "$delete_mode" ${refs[@]+"${refs[@]}"})
	return 0
}

# True when $1 contains a short-option cluster with 'f' in it: -f, -fu, -uf,
# etc. The [[:alnum:]]* run never crosses a second dash, so long options and
# words such as 'feature/fix-flaky' cannot match. Shared by fix_ci_allows_push
# (force-push) and check_worktree_remove (force-remove).
command_has_short_force_flag() {
	[[ "$1" =~ [[:space:]]-[[:alnum:]]*f ]]
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
	# Force refspec: a token starting with '+', as in 'origin +main:main'.
	if [[ "$command" =~ [[:space:]]--force ]] ||
		command_has_short_force_flag "$command" ||
		[[ "$command" =~ [[:space:]][+][^[:space:]] ]]; then
		fix_ci_push_denial_op="git push --force"
		fix_ci_push_denial_reason="The fix-ci loop squash-merges; it never rewrites history."
		return 1
	fi

	# --mirror deletes every remote ref that has no local counterpart, so it is
	# never in namespace no matter what the refspecs say.
	if [[ "$command" =~ [[:space:]]--mirror([[:space:]]|$) ]] || ! fix_ci_push_deletes_only_own; then
		fix_ci_push_denial_op="git push (delete)"
		fix_ci_push_denial_reason="Only the assistant's own fix-ci/* and plan/* branches may be deleted, never other history."
		return 1
	fi

	return 0
}

# Uses global $command (set per sub-command in the main loop). True only when
# every branch named for deletion belongs to a sanctioned namespace.
fix_ci_allows_branch_delete() {
	fix_ci_active || return 1

	local -a names=()
	local word
	git_parse_command "$command" || return 1
	for word in ${GIT_SUBCMD_ARGS[@]+"${GIT_SUBCMD_ARGS[@]}"}; do
		[[ "$word" == -* ]] && continue
		names+=("$word")
	done

	[[ ${#names[@]} -gt 0 ]] || return 1
	for word in "${names[@]}"; do
		ref_in_own_namespace "$word" || return 1
	done
	return 0
}

# ╭────────────────────────────────────────────────────────────╮
# │                   Protected main Branch                    │
# ╰────────────────────────────────────────────────────────────╯

# `git config claude.protectMain true` marks a repo whose trunk the assistant
# never writes to: work happens on a `plan/*` branch, and it reaches main as one
# squash commit the user makes through /release. Every subcommand that
# can add a commit to the checked-out branch is therefore blocked while HEAD is
# main or master — a fast-forward `pull` is the exception, since it only moves
# the branch to commits the remote already has.
#
# The key is read from the repo the command targets, resolved through
# git_target_dir exactly as the fix-ci marker is, so `git -C <other-repo> commit`
# is judged by that repo's config and not by the hook's cwd.
PROTECTED_MAIN_SUBCMDS='commit|merge|cherry-pick|revert|am|rebase|pull'

# Uses global $command (set per sub-command in the main loop).
main_is_protected() {
	local git_dir branch
	git_dir=$(current_target_git_dir) || return 1
	[[ $(git --no-optional-locks --git-dir="$git_dir" config --bool claude.protectMain 2>/dev/null) == true ]] || return 1
	branch=$(git --no-optional-locks --git-dir="$git_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 1
	[[ "$branch" == main || "$branch" == master ]]
}

# Uses global $command (set per sub-command in the main loop).
check_protected_main() {
	local subcmd
	subcmd=$(get_git_subcmd "$command") || return 0
	[[ "$subcmd" =~ ^($PROTECTED_MAIN_SUBCMDS)$ ]] || return 0
	[[ "$subcmd" == pull && "$command" =~ [[:space:]]--ff-only([[:space:]]|$) ]] && return 0
	main_is_protected || return 0
	block_destructive "git $subcmd" \
		"main is protected in this repo (claude.protectMain). Commit on a plan/* branch; plan work lands on main through /release, which the user runs."
}

# scripts/release.sh lands a plan branch on main and pushes it. It is the user's
# step, and its inner git commands run where no subcommand parser can see them —
# so the invocation is blocked here, whatever path spells it and whether or not
# the fragment names a git subcommand at all. The one door is the `/release`
# skill, which raises a `$GIT_DIR/release-active` marker for the run; while that
# marker is fresh the invocation goes through.
#
# This rule reads the raw command itself rather than the sanitized fragments the
# other rules parse: a quoted path (`bash "scripts/release.sh"`) collapses to
# the placeholder there and would hide the invocation. Only the command-position
# word counts, so a commit message that merely names the script parses as `git`.

# Words that may stand between the fragment's start and the script without
# hiding it: interpreters, and the wrappers that run a command under a modified
# environment or process. Matched on basename, so `/bin/bash` and
# `/usr/bin/env bash` are prefixes too.
release_prefix_word() {
	case "${1##*/}" in
	bash | sh | zsh | dash | ksh | env | command | exec | time | nohup | nice | sudo | source | .) return 0 ;;
	esac
	return 1
}

# The subcommands that act on the repo, and so make the word before them an
# invocation wherever it sits. `status` is absent on purpose: it only reports.
release_acting_subcommand() {
	case "$1" in
	start | merge | finish) return 0 ;;
	esac
	return 1
}

# True when fragment $1 invokes the release script in a way that needs the
# marker. Two shapes count:
#
#   - the script followed by a subcommand that acts on the repo, whatever words
#     precede it, so a runner no prefix list knows (`timeout 5 …`, `uv run …`,
#     `xargs …`) cannot hide the invocation;
#   - the script in command position with a first argument other than `status`,
#     which covers a run that names no subcommand at all. `status` is exempt in
#     that one position only — the one the script itself reads a subcommand
#     from — never further down the argument list.
#
# Text that merely names the script (`cat scripts/release.sh`, a commit message)
# matches neither: nothing it can act on follows, and it is not the command.
release_fragment_invokes() {
	local word prefix_seen=false next=0
	local -a words=()
	# read -ra splits on whitespace without letting a word glob.
	read -ra words <<<"$1"
	for word in ${words[@]+"${words[@]}"}; do
		next=$((next + 1))
		if [[ "${word##*/}" == release.sh ]] && release_acting_subcommand "${words[next]-}"; then
			return 0
		fi
	done

	next=0
	for word in ${words[@]+"${words[@]}"}; do
		next=$((next + 1))
		if release_prefix_word "$word"; then
			prefix_seen=true
			continue
		fi
		# Assignments run ahead of the command word, as `FOO=1 cmd` and as
		# `env FOO=1 cmd`; options belong to a prefix already seen.
		if [[ "$word" == [[:alpha:]_]*=* ]]; then
			continue
		fi
		if $prefix_seen && [[ "$word" == -* ]]; then
			continue
		fi
		[[ "${word##*/}" == release.sh ]] || return 1
		[[ "${words[next]-}" == status ]] && return 1
		return 0
	done
	return 1
}

# True when /release sanctions a run in the repo the fragment targets. The
# marker shares the fix-ci freshness window, so one left behind by an interrupted
# skill ages out instead of standing the door open.
# Uses global $command (set per fragment by check_release_invocation).
release_active() {
	local git_dir
	git_dir=$(current_target_git_dir) || return 1
	marker_fresh "$git_dir/$RELEASE_MARKER"
}

# Uses global $scannable.
check_release_invocation() {
	local reading fragment
	# One pass walks the quoted regions, so a newline means what the shell
	# means by it: inside a region it is data and folds to a space, keeping a
	# commit message that names the script at the start of a line out of
	# command position; outside one it separates fragments like `;`, so an
	# invocation on its own line is seen.
	#
	# Quote characters and backslashes are deleted outright rather than
	# collapsed, so the script stays visible however its path is spelled. That
	# merges quoted text into the surrounding words and splits on separators
	# that were really data — harmless, since a stray split only yields one
	# more fragment whose command-position word gets checked.
	reading=$(printf '%s' "$scannable" | awk -v q="'" '
		{ buf = buf $0 "\n" }
		END {
			gsub(/\\/, "", buf)
			region_re = "\"[^\"]*\"|" q "[^" q "]*" q
			while (match(buf, region_re)) {
				region = substr(buf, RSTART + 1, RLENGTH - 2)
				gsub(/\n/, " ", region)
				out = out substr(buf, 1, RSTART - 1) region
				buf = substr(buf, RSTART + RLENGTH)
			}
			out = out buf
			gsub(/&&|\|\||[|;]/, "\n", out)
			printf "%s", out
		}')
	while IFS= read -r fragment; do
		release_fragment_invokes "$fragment" || continue
		# git_target_dir reads the fragment's own -C / --git-dir, the same way
		# the fix-ci marker is scoped to the repo a command aims at.
		command="$fragment"
		# Outside any repo there is no marker to consult and no plan branch to
		# land, so the run is left to fail on its own.
		git_target_dir "$command" >/dev/null || continue
		release_active && continue
		block_destructive "release.sh" \
			"This script runs only through /release, which raises the marker it needs. Report the branch as ready to ship instead."
	done <<<"$reading"
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
	is_git_subcmd "checkout" &&
		block_destructive "git checkout" "Banned. Use 'git switch' for branches, 'git restore --staged' for unstaging."

	is_git_subcmd "switch" && [[ "$command" =~ [[:space:]](-f|--force|--discard-changes)([[:space:]]|$) ]] &&
		block_destructive "git switch --force" "Force-switch discards uncommitted changes."

	# ── Reset / Clean / Stash ────────────────────────────────────
	# git reset (all forms — even soft/mixed reset can move HEAD or unstage unexpectedly)
	is_git_subcmd "reset" &&
		block_destructive "git reset" "Resets HEAD, staging area, or working tree. Use git restore --staged to unstage."

	is_git_subcmd "clean" && [[ "$command" =~ -[fdxn]*f ]] &&
		block_destructive "git clean -f" "Permanently deletes untracked files."

	# git stash (all forms — stash then lose is a common failure mode)
	is_git_subcmd "stash" &&
		block_destructive "git stash" "Stashing risks losing uncommitted work."

	# ── Branch ───────────────────────────────────────────────────
	is_git_subcmd "branch" && [[ "$command" =~ [[:space:]]-D ]] && ! fix_ci_allows_branch_delete &&
		block_destructive "git branch -D" "Force-deletes branch, may lose unmerged commits."

	# ── Restore ──────────────────────────────────────────────────
	# Restore and rm are judged on the subcommand's own arguments: option-shaped
	# text in a global option value (`git -c a.b=--staged restore .`) must not
	# unlock them. Leading space so the first argument also follows whitespace.
	local subcmd_args
	if is_git_subcmd "restore"; then
		git_parse_command "$command"
		subcmd_args=" ${GIT_SUBCMD_ARGS[*]-}"
		# --worktree / -W discards working tree changes even when combined with --staged
		[[ "$subcmd_args" =~ [[:space:]](-W|--worktree)([[:space:]]|$) ]] &&
			block_destructive "git restore --worktree" "Discards uncommitted changes to files."

		[[ ! "$subcmd_args" =~ [[:space:]]--staged([[:space:]]|$) ]] &&
			block_destructive "git restore (discard)" "Discards uncommitted changes to files."
	fi

	# ── Rm ───────────────────────────────────────────────────────
	if is_git_subcmd "rm"; then
		git_parse_command "$command"
		subcmd_args=" ${GIT_SUBCMD_ARGS[*]-}"
		[[ "$subcmd_args" =~ [[:space:]]--cached([[:space:]]|$) ]] && return 0
		[[ "$subcmd_args" =~ [[:space:]]--dry-run([[:space:]]|$) ]] && return 0
		# Bundled short flags containing n (dry-run): -n, -rn, -fn, etc.
		[[ "$subcmd_args" =~ [[:space:]]-[a-zA-Z]*n ]] && return 0
		block_destructive "git rm" "Deletes files from the working tree. Use --cached to only unstage."
	fi

	# ── Reflog / prune ──────────────────────────────────────────
	is_git_subcmd "reflog" && [[ "$command" =~ [[:space:]](expire|delete)([[:space:]]|$) ]] &&
		block_destructive "git reflog expire/delete" "Destroys reflog entries, making recovery impossible."

	is_git_subcmd "prune" &&
		block_destructive "git prune" "Removes unreachable objects. Let git gc handle pruning safely."

	is_git_subcmd "gc" && [[ "$command" =~ [[:space:]]--prune= ]] &&
		block_destructive "git gc --prune" "Immediate pruning risks losing recoverable objects."

	# ── Commit ───────────────────────────────────────────────────

	# ── History extraction with redirect (overwrite working tree) ─
	if is_git_subcmd "show" || is_git_subcmd "cat-file"; then
		local _stripped
		_stripped=$(printf '%s' "$command" | sed 's/[2-9]>//g')
		[[ "$_stripped" =~ \> ]] &&
			block_destructive "git show/cat-file with redirect" \
				"Writing git history content to files can overwrite working tree changes."
	fi

	# ── Patch reversal ───────────────────────────────────────────
	is_git_subcmd "apply" && [[ "$command" =~ [[:space:]](-R|--reverse)([[:space:]]|$) ]] &&
		block_destructive "git apply --reverse" "Reverse-applying patches can discard changes."

	# ── Rebase ───────────────────────────────────────────────────
	if is_git_subcmd "rebase"; then
		local top
		top=$(git_on_target "$command" rev-parse --show-toplevel 2>/dev/null) || return 0
		sh_git_dirty "$top" >/dev/null || return 0
		block_destructive "git rebase (dirty)" "Rebasing with uncommitted changes risks losing work."
	fi
}

# ╭────────────────────────────────────────────────────────────╮
# │                    Command Checking                        │
# ╰────────────────────────────────────────────────────────────╯

# Uses global $command (set per sub-command in the main loop). Paths and the
# plan-file scan are judged in the repo the command targets.
check_add_safety() {
	local pattern args_text
	git_parse_command "$command" || return 0
	# Leading space so every argument, the first included, follows whitespace.
	args_text=" ${GIT_SUBCMD_ARGS[*]-}"

	if pattern=$(find_plan_pattern "$args_text"); then
		printf "Error: Cannot stage plan files matching '%s'. These are temporary analysis files.\n" "$pattern" >&2
		exit 2
	fi

	if [[ "$args_text" =~ [[:space:]](\.|-[aA]|--all)([[:space:]]|$) ]]; then
		local root
		root=$(git_on_target "$command" rev-parse --show-toplevel 2>/dev/null) || root=""
		if [[ -n "$root" ]]; then
			local pending_files
			pending_files=$(git --no-optional-locks -C "$root" ls-files --others --modified --exclude-standard 2>/dev/null)
			check_plan_files "$pending_files" || exit 2
		fi
	fi

	# Block all force-adds — -f/--force bypasses gitignore, the only
	# reason to use it is to track ignored files, which is forbidden.
	if [[ "$args_text" =~ [[:space:]](-f|--force)([[:space:]]|$) ]]; then
		block_destructive "git add --force" \
			"Force-adding bypasses gitignore rules. Never track ignored files."
	fi

	# Check explicitly named paths against gitignore (local + global + .git/info/exclude)
	local _past_dashdash=false _word _path
	local -a _add_paths=()
	for _word in ${GIT_SUBCMD_ARGS[@]+"${GIT_SUBCMD_ARGS[@]}"}; do
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
		if git_on_target "$command" check-ignore -q -- "$_path" 2>/dev/null; then
			block_destructive "git add (gitignored)" \
				"'$_path' matches a gitignore rule (local or global). Do not track ignored files."
		fi
	done
}

# Uses global $command (set per sub-command in the main loop).
check_worktree_remove() {
	git_parse_command "$command" && [[ "$GIT_SUBCMD" == worktree ]] || return 0
	local -a wt_args=(${GIT_SUBCMD_ARGS[@]+"${GIT_SUBCMD_ARGS[@]}"})
	((${#wt_args[@]} > 0)) && [[ "${wt_args[0]}" == remove ]] || return 0

	# --force exists to override git's own refusal to remove a dirty worktree,
	# so it is banned outright like `git branch -D`, whatever the path is.
	if [[ "$command" =~ [[:space:]]--force([[:space:]]|$) ]] ||
		command_has_short_force_flag "$command"; then
		block_destructive "git worktree remove --force" \
			"Force-removal deletes a worktree that still holds uncommitted work."
	fi

	# Extract worktree path: last non-flag argument after 'remove'
	local wt_path="" word
	for word in "${wt_args[@]:1}"; do
		[[ "$word" != -* ]] && wt_path="$word"
	done

	# A missing path, a path or -C directory that arrived quoted (collapsed to
	# the placeholder, as in a loop over "$wt"), or one that does not resolve
	# all leave the worktree unverifiable — fail closed rather than wave the
	# removal through. The path is judged where git itself would look: under
	# the command's -C directory, never the hook's cwd.
	if [[ -n "$wt_path" ]]; then
		wt_path=$(git_command_path "$command" "$wt_path")
	fi
	if [[ -z "$wt_path" || "$wt_path" == *"$QUOTED_PLACEHOLDER"* || ! -d "$wt_path" ]]; then
		block_destructive "git worktree remove (unverifiable path)" \
			"The guard cannot confirm the worktree is clean. Re-run with a literal, unquoted path."
	fi

	if sh_git_dirty "$wt_path" --untracked >/dev/null; then
		block_destructive "git worktree remove (dirty)" \
			"Worktree at '$wt_path' has uncommitted changes. Commit work before removing."
	fi
}

# Sets global $command so is_git_subcmd and regex checks work.
check_single_command() {
	command="$1"

	# Run outside any repo, a command that names none has nothing to guard. One
	# that names a repo is still judged, even when that repo does not resolve:
	# its syntax-level bans hold, and state checks read nothing in its place.
	if ! git_target_dir "$command" >/dev/null && ! git_names_repo "$command"; then
		return 0
	fi

	check_protected_main

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
		root=$(git_on_target "$command" rev-parse --show-toplevel 2>/dev/null) || return 0
		local staged_files
		staged_files=$(git --no-optional-locks -C "$root" diff --cached --name-only 2>/dev/null)
		check_plan_files "$staged_files" || exit 2
	fi

	check_worktree_remove
	check_destructive_operations
}

# ╭────────────────────────────────────────────────────────────╮
# │                      Heredoc Bodies                        │
# ╰────────────────────────────────────────────────────────────╯
# A heredoc body is an argument, not a script: `git commit -F - <<'EOF'` hands
# its lines to git, which only reads them. Both splitters would otherwise take
# each body line for a fragment and block a commit message that names a guarded
# command or the release script. So the body is dropped for the consumers that
# can only read their input, and kept — scanned line by line, as any other
# fragment is — for anything that could run it (`bash`, `eval`, a word this list
# does not know), which is the closed side of the door.
#
# The line carrying the operator is always scanned: `git push --force <<EOF` is
# a push whatever it is fed.
readonly HEREDOC_READERS=" git cat tee head tail grep sort wc gh jq "

# Dropping runs to the terminator line, and only when that line is really there:
# without one the `<<` is prose inside a message far more often than a heredoc,
# and swallowing the rest of the command would hide whatever follows it.
scannable=$(printf '%s' "$full_command" | awk -v q="'" -v readers="$HEREDOC_READERS" '
	# The delimiter of the first heredoc opened on the line, or "" for none;
	# sets hd_prefix to the text before the operator. Blanking `<<<` keeps the
	# offsets while taking herestrings, which read one word, out of the running.
	function delimiter(line,   probe, word) {
		probe = line
		gsub(/<<</, "   ", probe)
		if (!match(probe, "<<-?[[:space:]]*(\"[^\"]*\"|" q "[^" q "]*" q "|[[:alnum:]_]+)")) return ""
		hd_prefix = substr(probe, 1, RSTART - 1)
		word = substr(probe, RSTART, RLENGTH)
		sub(/^<<-?[[:space:]]*/, "", word)
		gsub("\"", "", word)
		gsub(q, "", word)
		return word
	}
	# The command the heredoc feeds: the first word of the last fragment before
	# the operator, so a substitution such as `-m "$(cat <<EOF` answers `cat`.
	# An assignment or a wrapper in that slot answers neither, and the body is
	# scanned.
	function consumer(prefix,   n, parts, w) {
		gsub(/&&|\|\||[|;()`{}]/, "\n", prefix)
		n = split(prefix, parts, "\n")
		w = parts[n]
		sub(/^[[:space:]]+/, "", w)
		sub(/[[:space:]].*/, "", w)
		gsub("\"", "", w)
		gsub(q, "", w)
		sub(/.*\//, "", w)
		return w
	}
	# The line closing delimiter $2, from line $1 on, or 0 when none does. A
	# `<<-` terminator may be indented, so both ends are trimmed.
	function terminator(from, word,   i, t) {
		for (i = from; i <= NR; i++) {
			t = lines[i]
			sub(/^[[:space:]]+/, "", t)
			sub(/[[:space:]]+$/, "", t)
			if (t == word) return i
		}
		return 0
	}
	{ lines[NR] = $0 }
	END {
		for (i = 1; i <= NR; i++) {
			print lines[i]
			word = delimiter(lines[i])
			if (word == "") continue
			if (index(readers, " " consumer(hd_prefix) " ") == 0) continue
			closing = terminator(i + 1, word)
			if (closing > 0) i = closing
		}
	}')

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

sanitized=$(printf '%s' "$scannable" | awk -v q="'" -v ph="$QUOTED_PLACEHOLDER" '
	{ buf = buf $0 "\n" }
	END {
		gsub(/\\./, " ", buf)
		gsub(/"[^"]*"/, ph, buf)
		gsub(q "[^" q "]*" q, ph, buf)
		gsub(/&&|\|\||[|;]/, "\n", buf)
		printf "%s", buf
	}')

check_release_invocation

while IFS= read -r fragment; do
	fragment="${fragment#"${fragment%%[![:space:]]*}"}"
	fragment="${fragment%"${fragment##*[![:space:]]}"}"
	[[ -z "$fragment" ]] && continue
	check_single_command "$fragment"
done <<<"$sanitized"

exit 0
