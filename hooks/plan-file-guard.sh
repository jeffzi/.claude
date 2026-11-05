#!/usr/bin/env bash
set -euo pipefail

# plan-file-guard.sh — PreToolUse Bash hook: keeps plan files (temporary
# analysis under .claude/plans/ and docs/plans/) out of git history.
#
# - `git add` naming a plan path is blocked.
# - `git add .`, `-A` and `--all` are blocked while the target repository has
#   an untracked or modified plan file they would stage.
# - `git commit` is blocked while the target repository has a plan file staged.
#
# Every rule reads the repository the invocation targets, as
# scripts/ils-invocations.sh resolves it — never the hook's cwd. An invocation
# with no known repository has nothing to read and is allowed. A read that
# fails, of the command or of a repository, blocks: the guard cannot vouch for
# what it did not see.
#
# Input: PreToolUse JSON on stdin (.tool_input.command, .cwd)
# Exit: 0 to allow, 2 to block with the reason on stderr

HOOK_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=plan-file-guard

readonly PLAN_PATTERNS=('.claude/plans/' 'docs/plans/')

# Prints the first PLAN_PATTERNS entry found in any of the paths $@, or fails
# when none holds one.
find_plan_pattern() {
	local path pattern
	for path in "$@"; do
		for pattern in "${PLAN_PATTERNS[@]}"; do
			if [[ "$path" == *"$pattern"* ]]; then
				printf '%s' "$pattern"
				return 0
			fi
		done
	done
	return 1
}

# Blocks when one of the paths $2.. holds a plan pattern; $1 is the action
# the message names.
block_plan_paths() {
	local action="$1" pattern
	shift
	pattern=$(find_plan_pattern "$@") || return 0
	die "Cannot $action plan files matching '$pattern'. These are temporary analysis files."
}

# Prints the work tree of git dir $1, or nothing for a bare repository. A
# linked worktree's private git dir names its work tree in its `gitdir` file;
# a main repository's work tree is core.worktree when set, else the directory
# holding the git dir.
work_tree_of() {
	local git_dir="$1" link
	if [[ -f "$git_dir/gitdir" ]]; then
		link=$(<"$git_dir/gitdir")
		printf '%s' "${link%/.git}"
	elif git --git-dir="$git_dir" config --get core.worktree >/dev/null; then
		git --git-dir="$git_dir" rev-parse --show-toplevel
	elif [[ "$(git --git-dir="$git_dir" rev-parse --is-bare-repository)" != true ]]; then
		printf '%s' "${git_dir%/*}"
	fi
}

# Blocks `git add` with arguments $2.. in the repository at git dir $1.
check_add() {
	local git_dir="$1" word work_tree pending
	shift
	block_plan_paths stage "$@"

	for word in "$@"; do
		case "$word" in
		. | -A | --all) ;;
		*) continue ;;
		esac
		work_tree=$(work_tree_of "$git_dir") ||
			die "cannot find the work tree of the repository at $git_dir"
		[[ -n "$work_tree" ]] || return 0
		# --no-optional-locks keeps the read from taking index.lock out from
		# under the git command it guards.
		pending=$(git --no-optional-locks -C "$work_tree" ls-files --others --modified --exclude-standard) ||
			die "cannot read the pending files of the repository at $work_tree"
		[[ -n "$pending" ]] || return 0
		local -a pending_files
		mapfile -t pending_files <<<"$pending"
		block_plan_paths stage/commit "${pending_files[@]}"
		return 0
	done
}

# Blocks `git commit` in the repository at git dir $1.
check_commit() {
	local git_dir="$1" staged
	staged=$(git --no-optional-locks --git-dir="$git_dir" diff --cached --name-only) ||
		die "cannot read the staged files of the repository at $git_dir"
	[[ -n "$staged" ]] || return 0
	local -a staged_files
	mapfile -t staged_files <<<"$staged"
	block_plan_paths stage/commit "${staged_files[@]}"
}

# Applies the rule for git subcommand $2 with arguments $3.. to the repository
# at git dir $1.
check_invocation() {
	local git_dir="$1" subcommand="$2"
	shift 2
	case "$subcommand" in
	add) check_add "$git_dir" "$@" ;;
	commit) check_commit "$git_dir" ;;
	esac
}

ils_each_git_invocation check_invocation
