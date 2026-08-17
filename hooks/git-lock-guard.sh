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

get_lock_age() {
	local lock_path="$1"
	# Single stat call avoids a TOCTOU window between existence check and read.
	# If the lock vanished between the timeout and this call, mod_time stays 0.
	local mod_time
	mod_time=$(stat -f %m "$lock_path" 2>/dev/null || echo 0)
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
