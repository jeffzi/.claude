#!/usr/bin/env bash
set -euo pipefail

# tdd-cycle-guard.sh — PreToolUse Bash hook: while a tdd-cycle agent runs, the
# orchestrator owns all commits, so `git add` and `git commit` are blocked in
# any repository whose git dir holds the `tdd-cycle-active` marker (raised and
# removed per agents/tdd-cycle.md).
#
# The marker is read from the repository the invocation targets, as
# scripts/ils-invocations.sh resolves it — never the hook's cwd. An invocation
# with no known repository has no marker to read and is allowed. A command
# whose git invocations cannot be read blocks: the guard cannot vouch for what
# it did not see.
#
# Input: PreToolUse JSON on stdin (.tool_input.command, .cwd)
# Exit: 0 to allow, 2 to block with the reason on stderr

HOOK_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
# shellcheck source=SCRIPTDIR/../scripts/ils-invocations.sh
. "$HOOK_DIR/../scripts/ils-invocations.sh"
PROG=tdd-cycle-guard

readonly MARKER_NAME=tdd-cycle-active

# Blocks `git <subcommand $2>` when it is add or commit and the git dir $1
# holds the marker.
check_marker() {
	local git_dir="$1" subcommand="$2"
	[[ "$subcommand" == add || "$subcommand" == commit ]] || return 0
	[[ -f "$git_dir/$MARKER_NAME" ]] || return 0
	{
		printf 'BLOCKED: git %s — a tdd-cycle agent is running and the orchestrator owns all commits.\n' "$subcommand"
		printf 'If you ARE the tdd-cycle agent: do not commit or stage; write your report instead.\n'
		printf "If no tdd-cycle agent is running (stale marker), remove '%s/%s' and retry.\n" "$git_dir" "$MARKER_NAME"
	} >&2
	exit 2
}

ils_each_git_invocation check_marker
