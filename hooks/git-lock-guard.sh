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

HOOK_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# Portable stat access, for the lock file's age.
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=git-lock-guard

# ╭────────────────────────────────────────────────────────────╮
# │          Index-Mutating Subcommands Check                  │
# ╰────────────────────────────────────────────────────────────╯

# True when `git <subcommand $1> <args $2…>` writes the index.
is_mutating() {
	local subcmd="$1" arg
	shift

	case "$subcmd" in
	add | commit | rm | mv | merge | cherry-pick | revert | am | pull | update-index | commit-tree)
		return 0
		;;
	restore)
		# --staged, or -S alone or in a short-option cluster (-SW). An `s` in a
		# cluster takes the rest of it as its tree (-sSTABLE), and `--` ends the
		# options, so neither is read as -S.
		for arg; do
			case "$arg" in
			--) return 1 ;;
			--staged) return 0 ;;
			--*) ;;
			-*)
				arg="${arg#-}"
				arg="${arg%%s*}"
				[[ "$arg" == *S* ]] && return 0
				;;
			esac
		done
		return 1
		;;
	*)
		return 1
		;;
	esac
}

# ╭────────────────────────────────────────────────────────────╮
# │              Lock File Waiting Logic                       │
# ╰────────────────────────────────────────────────────────────╯

wait_for_lock() {
	local lock_path="$1"
	local timeout_ms="${GIT_LOCK_GUARD_TIMEOUT_MS:-3000}"
	local elapsed=0

	# Poll for lock clearance
	while [[ -f "$lock_path" ]]; do
		if ((elapsed >= timeout_ms)); then
			break
		fi
		sleep 0.1
		((elapsed += 100))
	done

	if [[ -f "$lock_path" ]]; then
		return 1 # Lock persisted — timeout
	fi
	return 0 # Lock cleared — success
}

get_lock_age() {
	local lock_path="$1"
	# Single stat call avoids a TOCTOU window between existence check and read.
	# A lock that vanished in between, or a stat that cannot read it, leaves
	# mod_time at 0 — the diagnostic still prints, with an implausible age.
	local mod_time
	mod_time=$(sh_file_attr mtime "$lock_path") || mod_time=0
	printf "%d" "$(($(date +%s) - mod_time))"
}

print_diagnostic() {
	local lock_path="$1"
	local age
	age=$(get_lock_age "$lock_path")

	printf "Lock file %s exists (age: %d seconds)\n" "$lock_path" "$age" >&2

	# Try to get lsof output
	local lsof_output
	lsof_output=$(/usr/sbin/lsof "$lock_path" 2>/dev/null || echo "")

	if [[ -n "$lsof_output" ]]; then
		printf "Holders:\n%s\n" "$lsof_output" >&2
	else
		printf "(no lsof holders found)\n" >&2
	fi
}

# ╭────────────────────────────────────────────────────────────╮
# │                  Main Logic                                │
# ╰────────────────────────────────────────────────────────────╯

# ils_each_git_invocation callback: waits on the index lock in git dir $1 when
# `git <subcommand $2> <args $3…>` writes the index, and blocks when it persists.
wait_on_index_lock() {
	local git_dir="$1" lock_path
	shift
	is_mutating "$@" || return 0
	lock_path="$git_dir/index.lock"
	[[ -f "$lock_path" ]] || return 0
	wait_for_lock "$lock_path" && return 0
	print_diagnostic "$lock_path"
	exit 2
}

ils_each_git_invocation wait_on_index_lock
