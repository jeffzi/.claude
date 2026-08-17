#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │              Git Lock Guard Hook                           │
# ╰────────────────────────────────────────────────────────────╯
# Absorbs short races on .git/index.lock caused by parallel
# agents/sessions touching the same repo.
#
# Input: JSON on stdin with .tool_input.command
# Output: stderr on timeout with diagnostic info
# Exit: 0 to allow, 2 to block

command -v jq >/dev/null || exit 0

# Read JSON input
input=$(cat)
full_command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

[[ -z "$full_command" ]] && exit 0

[[ "$full_command" =~ ^[[:space:]]*git([[:space:]]|$) ]] || exit 0

git --no-optional-locks rev-parse --git-dir >/dev/null 2>&1 || exit 0

# git subcommand parsing, shared with hooks/git-guard.sh. The hook runs with
# cwd set to the repo it is guarding, so this is resolved from the script's
# own location — never relative to cwd or $HOME.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../scripts/git-parse.sh
. "$HOOK_DIR/../scripts/git-parse.sh"

# ╭────────────────────────────────────────────────────────────╮
# │          Index-Mutating Subcommands Check                  │
# ╰────────────────────────────────────────────────────────────╯

is_mutating() {
	local subcmd="$1"
	local cmd="$2"

	case "$subcmd" in
	# Index-mutating subcommands
	add | commit | rm | mv | merge | cherry-pick | revert | am | pull | update-index | commit-tree)
		return 0
		;;
	# restore is only mutating with --staged
	restore)
		[[ "$cmd" =~ --staged ]] && return 0
		return 1
		;;
	# Everything else is read-only
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

_detect_lock_stat_fmt() {
	if stat -f %m "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
		printf -- '-f %%m'
	elif stat -c %Y "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
		printf -- '-c %%Y'
	fi
}
_LOCK_STAT_FMT=$(_detect_lock_stat_fmt)

get_lock_age() {
	local lock_path="$1"
	# Single stat call avoids a TOCTOU window between existence check and read.
	# If the lock vanished between the timeout and this call, mod_time stays 0.
	local mod_time
	if [[ -n "$_LOCK_STAT_FMT" ]]; then
		# shellcheck disable=SC2086 # _LOCK_STAT_FMT must word-split into two arguments
		mod_time=$(stat $_LOCK_STAT_FMT "$lock_path" 2>/dev/null || echo 0)
	else
		mod_time=0
	fi
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

# Extract git directory path (handles worktrees and bare repos)
git_dir=$(git --no-optional-locks rev-parse --git-dir)
lock_path="$git_dir/index.lock"

subcmd=$(get_git_subcmd "$full_command") || exit 0

# If not a mutating command, allow immediately
if ! is_mutating "$subcmd" "$full_command"; then
	exit 0
fi

# If lock file doesn't exist, allow immediately
if [[ ! -f "$lock_path" ]]; then
	exit 0
fi

# Lock exists and this is a mutating command — wait for it
if ! wait_for_lock "$lock_path"; then
	# Timeout occurred
	print_diagnostic "$lock_path"
	exit 2
fi

# Lock cleared — allow
exit 0
