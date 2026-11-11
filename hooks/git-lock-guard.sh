#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │              Git Lock Guard Hook                           │
# ╰────────────────────────────────────────────────────────────╯
# Absorbs short races on .git/index.lock caused by parallel
# agents/sessions touching the same repo.
#
# Every index-mutating git invocation in the command waits on the lock of the
# repository it targets, as scripts/ils-invocations.sh resolves it — never the
# hook's cwd. An invocation with no known repository has no lock to wait on and
# is allowed. A command whose git invocations cannot be read blocks: the guard
# cannot vouch for what it did not see.
#
# Input: PreToolUse JSON on stdin (.tool_input.command, .cwd)
# Output: stderr on timeout with diagnostic info
# Exit: 0 to allow, 2 to block

# `bash hook.sh` run from inside hooks/ leaves no slash to strip a directory at.
HOOK_SOURCE=${BASH_SOURCE[0]}
[[ "$HOOK_SOURCE" == */* ]] || HOOK_SOURCE="./$HOOK_SOURCE"
HOOK_DIR=$(cd "${HOOK_SOURCE%/*}" && pwd)
# Portable stat access, for the lock file's age.
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=git-lock-guard
sh_fail_closed

# True when `git <subcommand $1> <args $2…>` writes the index.
is_mutating() {
	local subcmd="$1"
	shift

	case "$subcmd" in
	add | commit | rm | mv | merge | cherry-pick | revert | am | pull | update-index | commit-tree | switch | checkout | reset | stash | rebase | read-tree | checkout-index)
		return 0
		;;
	apply)
		# --index, --cached, and --3way/-3 (which implies --index) touch the index.
		# A `p` or `C` in a cluster takes the rest of it as its value (-p3 strips
		# three path components, -C3 sets context lines), so neither is read as -3.
		ils_git_has_option 3 pC "--index --cached --3way" "$@"
		;;
	restore)
		# --staged or -S touch the index. An `s` in a cluster takes the rest of it
		# as its tree (-sSTABLE), so it is not read as -S.
		ils_git_has_option S s --staged "$@"
		;;
	*)
		return 1
		;;
	esac
}

wait_for_lock() {
	local lock_path="$1"
	local timeout_ms="${GIT_LOCK_GUARD_TIMEOUT_MS:-3000}"
	local elapsed=0
	local poll_seconds=0.1 poll_ms=100

	while [[ -f "$lock_path" ]]; do
		if ((elapsed >= timeout_ms)); then
			break
		fi
		sleep "$poll_seconds"
		((elapsed += poll_ms))
	done

	if [[ -f "$lock_path" ]]; then
		return 1
	fi
	return 0
}

# Prints the age in seconds of lock $1. Fails when stat cannot read it: the lock
# vanished since the caller saw it, or no stat dialect works.
get_lock_age() {
	local lock_path="$1" mod_time
	# Single stat call avoids a TOCTOU window between existence check and read.
	mod_time=$(sh_file_attr mtime "$lock_path") || return 1
	printf "%d" "$(($(date +%s) - mod_time))"
}

lock_diagnostic() {
	local lock_path="$1" age=unknown seconds lsof_output
	seconds=$(get_lock_age "$lock_path") && age="$seconds seconds"

	printf "Lock file %s exists (age: %s)\n" "$lock_path" "$age"

	if ! command -v lsof >/dev/null 2>&1; then
		printf "(lsof unavailable: holders unknown)\n"
		return 0
	fi

	# lsof exits 1 when no process holds the file; that is the empty-output case.
	lsof_output=$(lsof "$lock_path" 2>/dev/null) || lsof_output=""

	if [[ -n "$lsof_output" ]]; then
		printf "Holders:\n%s\n" "$lsof_output"
	else
		printf "(no lsof holders found)\n"
	fi
}

# ils_each_git_invocation callback: waits on the index lock in git dir $1 when
# `git <subcommand $2> <args $3…>` writes the index, and blocks when it persists.
wait_on_index_lock() {
	local git_dir="$1" lock_path
	shift
	is_mutating "$@" || return 0
	lock_path="$git_dir/index.lock"
	[[ -f "$lock_path" ]] || return 0
	wait_for_lock "$lock_path" && return 0
	die "$(lock_diagnostic "$lock_path")"
}

main() {
	ils_each_git_invocation wait_on_index_lock
}

main "$@"
