#!/usr/bin/env bash
set -euo pipefail

# plan-file-guard.sh — PreToolUse Bash hook: keeps plan files (temporary
# analysis under .claude/plans/ and docs/plans/) out of git history.
#
# - `git add` naming a plan path is blocked.
# - `git add .`, `-A` and `--all` are blocked while the target repository has
#   an untracked or modified plan file they would stage.
# - `git add <dir>`, for a directory that holds a plan directory (`docs`,
#   `.claude`, `./docs/plans`), is blocked while the target repository has an
#   untracked or modified plan file under it.
# - `git add -u` and `--update` are blocked while the target repository has a
#   modified tracked plan file.
# - `git commit` is blocked while the target repository has a plan file staged,
#   and `git commit -a` (`--all`, `-am`) also while it has a modified tracked
#   plan file.
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

# Blocks when `git ls-files` with options $2.., run in the work tree of git dir
# $1, lists a plan file. A bare repository has no work tree and nothing to list.
block_listed_plan_files() {
	local git_dir="$1" work_tree listed
	shift
	work_tree=$(work_tree_of "$git_dir") ||
		die "cannot find the work tree of the repository at $git_dir"
	[[ -n "$work_tree" ]] || return 0
	# --no-optional-locks keeps the read from taking index.lock out from
	# under the git command it guards.
	listed=$(git --no-optional-locks -C "$work_tree" ls-files "$@") ||
		die "cannot read the pending files of the repository at $work_tree"
	[[ -n "$listed" ]] || return 0
	# A read loop, not mapfile: macOS ships bash 3.2, which has no mapfile.
	local -a listed_files=()
	local path
	while IFS= read -r path; do
		listed_files+=("$path")
	done <<<"$listed"
	block_plan_paths stage/commit "${listed_files[@]}"
}

# Prints pathspec $1 as a directory relative to the work tree root — leading
# `./` and trailing `/` dropped — when it names a directory holding a
# PLAN_PATTERNS directory, or fails when it cannot hold one.
plan_holding_dir() {
	local dir="$1" pattern
	while [[ "$dir" == ./* ]]; do
		dir="${dir#./}"
	done
	while [[ "$dir" == */ ]]; do
		dir="${dir%/}"
	done
	[[ -n "$dir" ]] || return 1
	for pattern in "${PLAN_PATTERNS[@]}"; do
		if [[ "$pattern" == "$dir/"* ]]; then
			printf '%s' "$dir"
			return 0
		fi
	done
	return 1
}

# Blocks `git add` with arguments $2.. in the repository at git dir $1.
check_add() {
	local git_dir="$1" word dir
	shift
	block_plan_paths stage "$@"

	for word in "$@"; do
		case "$word" in
		. | -A | --all)
			block_listed_plan_files "$git_dir" --others --modified --exclude-standard
			return 0
			;;
		-u | --update)
			block_listed_plan_files "$git_dir" --modified
			return 0
			;;
		esac
		if dir=$(plan_holding_dir "$word"); then
			block_listed_plan_files "$git_dir" --others --modified --exclude-standard -- "$dir"
		fi
	done
}

# Succeeds when `git commit` arguments $@ hold -a or --all, alone or inside a
# short-option cluster. A cluster ends at the first option that takes an
# argument, since the rest of the word is that argument (`-ma` is the message
# "a").
commit_stages_all() {
	local word i
	for word in "$@"; do
		case "$word" in
		--) return 1 ;;
		--all) return 0 ;;
		-[!-]*) ;;
		*) continue ;;
		esac
		for ((i = 1; i < ${#word}; i++)); do
			case "${word:i:1}" in
			a) return 0 ;;
			[CcmFtuS]) break ;;
			esac
		done
	done
	return 1
}

# Blocks `git commit` with arguments $2.. in the repository at git dir $1.
check_commit() {
	local git_dir="$1" staged
	shift
	staged=$(git --no-optional-locks --git-dir="$git_dir" diff --cached --name-only) ||
		die "cannot read the staged files of the repository at $git_dir"
	if [[ -n "$staged" ]]; then
		# A read loop, not mapfile: macOS ships bash 3.2, which has no mapfile.
		local -a staged_files=()
		local path
		while IFS= read -r path; do
			staged_files+=("$path")
		done <<<"$staged"
		block_plan_paths stage/commit "${staged_files[@]}"
	fi
	if commit_stages_all "$@"; then
		block_listed_plan_files "$git_dir" --modified
	fi
}

# Applies the rule for git subcommand $2 with arguments $3.. to the repository
# at git dir $1.
check_invocation() {
	local git_dir="$1" subcommand="$2"
	shift 2
	case "$subcommand" in
	add) check_add "$git_dir" "$@" ;;
	commit) check_commit "$git_dir" "$@" ;;
	esac
}

ils_each_git_invocation check_invocation
