#!/usr/bin/env bash
set -euo pipefail

# plan-file-guard.sh — PreToolUse Bash hook: keeps plan files (temporary
# analysis under .claude/plans/ and docs/plans/) out of git history.
#
# - `git add` naming a plan path is blocked.
# - `git add .`, `-A` and `--all` are blocked while the target repository has
#   an untracked or modified plan file they would stage.
# - `git add <pathspec>` is blocked while the target repository has an
#   untracked or modified plan file the pathspec matches (`docs`, `.claude`,
#   `./docs/plans`, `./`, `:/`, globs), resolved from the directory the shell
#   runs the command in. `-A` and `-u` are also read inside short-option
#   clusters (`-vA`).
# - `git add -f` (`--force`, `-vf`) stages ignored files too, so with it the
#   whole-tree and pathspec rules also list ignored plan files.
# - `git add -u` and `--update` are blocked while the target repository has a
#   modified tracked plan file.
# - `git commit` is blocked while the target repository has a plan file staged,
#   and `git commit -a` (`--all`, `-am`) also while it has a modified tracked
#   plan file. `git commit <pathspec>` is blocked while a modified tracked plan
#   file matches the pathspec.
#
# Every rule reads the repository the invocation targets, as
# scripts/ils-invocations.sh resolves it — never the hook's cwd. An invocation
# with no known repository has nothing to read and is allowed. A read that
# fails, of the command or of a repository, blocks: the guard cannot vouch for
# what it did not see.
#
# Input: PreToolUse JSON on stdin (.tool_input.command, .cwd)
# Exit: 0 to allow, 2 to block with the reason on stderr

# `bash hook.sh` run from inside hooks/ leaves no slash to strip a directory at.
HOOK_SOURCE=${BASH_SOURCE[0]}
[[ "$HOOK_SOURCE" == */* ]] || HOOK_SOURCE="./$HOOK_SOURCE"
HOOK_DIR=$(cd "${HOOK_SOURCE%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=plan-file-guard
sh_fail_closed

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
# Fails when git cannot answer.
work_tree_of() {
	local git_dir="$1" link bare status=0
	if [[ -f "$git_dir/gitdir" ]]; then
		link=$(<"$git_dir/gitdir") || return 1
		printf '%s' "${link%/.git}"
		return 0
	fi
	# `config --get` exits 1 for an unset key; any other status is a failed read.
	git --git-dir="$git_dir" config --get core.worktree >/dev/null || status=$?
	case "$status" in
	0) git --git-dir="$git_dir" rev-parse --show-toplevel ;;
	1)
		bare=$(git --git-dir="$git_dir" rev-parse --is-bare-repository) || return 1
		[[ "$bare" == true ]] || printf '%s' "${git_dir%/*}"
		;;
	*) return 1 ;;
	esac
}

# Blocks when the lines in $1, one path per line, hold a plan file.
block_plan_lines() {
	local lines="$1" path
	[[ -n "$lines" ]] || return 0
	# A read loop, not mapfile: macOS ships bash 3.2, which has no mapfile.
	local -a files=()
	while IFS= read -r path; do
		files+=("$path")
	done <<<"$lines"
	block_plan_paths stage/commit "${files[@]}"
}

# Blocks when `git ls-files` with options $3.., run in the work tree of git dir
# $1, lists a plan file. A bare repository has no work tree and nothing to list.
# $2 is the directory the invocation runs in: pathspecs among the options
# resolve against it when it is a directory, else against the work tree root.
# Listed paths are always relative to the work tree root.
block_listed_plan_files() {
	local git_dir="$1" from="$2" work_tree listed
	shift 2
	work_tree=$(work_tree_of "$git_dir") ||
		die "cannot find the work tree of the repository at $git_dir"
	[[ -n "$work_tree" ]] || return 0
	# --no-optional-locks keeps the read from taking index.lock out from
	# under the git command it guards.
	local -a git_cmd=(git --no-optional-locks -C "$work_tree")
	if [[ -n "$from" && -d "$from" ]]; then
		git_cmd=(git --no-optional-locks -C "$from" --git-dir="$git_dir" --work-tree="$work_tree")
	fi
	listed=$("${git_cmd[@]}" ls-files --full-name "$@") ||
		die "cannot read the pending files of the repository at $work_tree"
	block_plan_lines "$listed"
}

# Blocks `git add` with arguments $3.. run from directory $2 in the repository
# at git dir $1. Every pathspec is resolved by the listing of what it would
# stage, so `./`, `:/`, globs and paths relative to $2 reach the files they
# name.
check_add() {
	local git_dir="$1" from="$2" word i past_options=0 all=0 update=0 force=0
	local -a pathspecs=() pending=(--others --modified)
	shift 2
	block_plan_paths stage "$@"

	for word in "$@"; do
		[[ -n "$word" ]] || continue
		if ((past_options)); then
			pathspecs+=("$word")
			continue
		fi
		case "$word" in
		--) past_options=1 ;;
		. | --all) all=1 ;;
		--update) update=1 ;;
		--force) force=1 ;;
		--*) ;;
		-?*)
			# A short-option cluster: `-vA` is -v and -A. No short option of
			# `git add` takes an argument.
			for ((i = 1; i < ${#word}; i++)); do
				case "${word:i:1}" in
				A) all=1 ;;
				u) update=1 ;;
				f) force=1 ;;
				esac
			done
			;;
		*) pathspecs+=("$word") ;;
		esac
	done

	((force)) || pending+=(--exclude-standard)
	if ((all)); then
		block_listed_plan_files "$git_dir" "" "${pending[@]}"
	fi
	if ((update)); then
		block_listed_plan_files "$git_dir" "" --modified
	fi
	if ((${#pathspecs[@]} > 0)); then
		block_listed_plan_files "$git_dir" "$from" "${pending[@]}" -- "${pathspecs[@]}"
	fi
}

# Blocks `git commit` with arguments $3.. run from directory $2 in the
# repository at git dir $1. A pathspec makes the commit take the working-tree
# content of the tracked files it matches, so a modified plan file it matches
# is blocked.
check_commit() {
	local git_dir="$1" from="$2" staged word i skip_value=0 past_options=0
	local -a pathspecs=()
	shift 2
	staged=$(git --no-optional-locks --git-dir="$git_dir" diff --cached --name-only) ||
		die "cannot read the staged files of the repository at $git_dir"
	block_plan_lines "$staged"
	if ils_git_has_option a "$ILS_GIT_COMMIT_VALUE_SHORTS$ILS_GIT_COMMIT_ATTACHED_SHORTS" --all "$@"; then
		block_listed_plan_files "$git_dir" "" --modified
	fi

	# The non-option words are pathspecs; the word after an option that takes
	# its value as a separate word is that value.
	for word in "$@"; do
		if ((skip_value)); then
			skip_value=0
			continue
		fi
		[[ -n "$word" ]] || continue
		if ((past_options)); then
			pathspecs+=("$word")
			continue
		fi
		case "$word" in
		--) past_options=1 ;;
		--message | --file | --reuse-message | --reedit-message | --template | \
			--author | --date | --cleanup | --fixup | --squash | --trailer | \
			--pathspec-from-file)
			skip_value=1
			;;
		--*) ;;
		-?*)
			for ((i = 1; i < ${#word}; i++)); do
				case "${word:i:1}" in
				["$ILS_GIT_COMMIT_VALUE_SHORTS"])
					if ((i == ${#word} - 1)); then
						skip_value=1
					fi
					break
					;;
				["$ILS_GIT_COMMIT_ATTACHED_SHORTS"]) break ;;
				esac
			done
			;;
		*) pathspecs+=("$word") ;;
		esac
	done
	if ((${#pathspecs[@]} > 0)); then
		block_plan_paths stage/commit "${pathspecs[@]}"
		block_listed_plan_files "$git_dir" "$from" --modified -- "${pathspecs[@]}"
	fi
}

# Applies the rule for git subcommand $2 with arguments $4.. run from directory
# $3 to the repository at git dir $1.
check_invocation() {
	local git_dir="$1" subcommand="$2" from="$3"
	shift 3
	case "$subcommand" in
	add) check_add "$git_dir" "$from" "$@" ;;
	commit) check_commit "$git_dir" "$from" "$@" ;;
	esac
}

# ils_each_invocation callback: like ils_call_git_callback, but keeps the
# directory the invocation runs in, which pathspecs resolve against.
call_check_invocation() {
	local tool="$1" git_dir="$2" subcommand="$3" from="$4" word
	local -a literals=()
	shift 4
	[[ "$tool" == git && -n "$git_dir" ]] || return 0
	# A word that is not a literal stays in place as an empty string: dropping
	# it would shift the words after it into its slot, and the value of an
	# option such as -m would then be read as a pathspec. check_add and
	# check_commit ignore empty words.
	for word; do
		if [[ "$word" == =* ]]; then
			literals+=("${word:1}")
		else
			literals+=("")
		fi
	done
	check_invocation "$git_dir" "$subcommand" "$from" ${literals[@]+"${literals[@]}"}
}

main() {
	ils_each_invocation call_check_invocation
}

main "$@"
