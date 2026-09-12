#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │           Collaboration Reminder Hook                      │
# ╰────────────────────────────────────────────────────────────╯
# Re-injects the propose-decisions / answer-questions-first
# policy on every user prompt and after compaction, so it stays
# salient late in long sessions.
#
# When execute-plan --unattended has raised its marker in the git
# dir, the unattended variant is injected instead: the approved
# plan is the confirmation, so the propose-and-confirm clause
# would otherwise stall execution on every turn. The marker holds
# the session id that raised it and is honored only by that
# session — a marker left behind by an interrupted plan must not
# silently suppress the policy for every later session.
#
# Input: hook JSON on stdin (session_id)
# Output: reminder text on stdout (appended to context)
# Exit: always 0

readonly DEFAULT_POLICY="User policy: questions or pushback in the latest message are addressed before any tool call — answered or explicitly deferred; work pauses if the answer could change it. Decisions with alternatives are proposed and confirmed before acting. Bypass/auto mode is not autonomy."

readonly UNATTENDED_POLICY="User policy: an approved plan is executing unattended — the plan is the confirmation. Questions in the latest message are still answered first. Findings are recorded and execution continues; halt only for verification red after two attempts, an unplanned behavior change something depends on, or a destructive/cross-repo boundary. Never ask whether to continue; never end the turn on a progress update."

# jq is required to extract session_id from hook JSON.
# Fall through to the default policy if missing — suppressing the reminder entirely
# would be worse than losing unattended detection.
command -v jq >/dev/null || {
	printf "Error: jq is required\n" >&2
	printf "%s\n" "$DEFAULT_POLICY"
	exit 0
}

unattended_for_session() {
	local session_id="$1" git_dir marker_session
	[[ -n "$session_id" ]] || return 1
	git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
	marker_session=$(cat "$git_dir/execute-plan-unattended" 2>/dev/null) || return 1
	[[ "$marker_session" == "$session_id" ]]
}

main() {
	local session_id
	# Valid input with no session_id → empty string (legitimate).
	# jq execution error → emit diagnostic, fall through to default policy.
	if ! session_id=$(jq -r '.session_id // empty' 2>/dev/null); then
		printf "Warning: failed to parse hook JSON\n" >&2
		session_id=""
	fi
	if unattended_for_session "$session_id"; then
		printf "%s\n" "$UNATTENDED_POLICY"
	else
		printf "%s\n" "$DEFAULT_POLICY"
	fi
}

main "$@"
