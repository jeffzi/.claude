#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                   Bash Exit Guard                          │
# ╰────────────────────────────────────────────────────────────╯
# PostToolUse hook: blocks Claude from proceeding when a Bash
# command fails. Outputs JSON { decision: "block", reason: ... }
# which forces Claude to acknowledge the error before continuing.
#
# Skip list: commands that routinely use non-zero exit for
# control flow (grep no-match, diff file-differs, etc.).

command -v jq >/dev/null || exit 0

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" == "Bash" ]] || exit 0

exit_code=$(printf '%s' "$input" | jq -r '.tool_response.exit_code // 0')
[[ "$exit_code" != "0" ]] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# ── Skip commands that use non-zero exit for control flow ────
# Extract the first word of the command (the binary being run)
first_word="${cmd%% *}"
# Also handle "command -v" and "test" expressions
case "$first_word" in
grep | rg | diff | test | which | false | true) exit 0 ;;
esac
case "$cmd" in
"command -v"* | "command  -v"*) exit 0 ;;
"["*) exit 0 ;;
esac

# ── Block: force Claude to address the error ─────────────────
jq -n \
	--arg reason "COMMAND FAILED (exit code $exit_code). Fix this error or surface it to the user before proceeding. Do NOT switch to a different file, config, or approach to avoid the error." \
	'{ "decision": "block", "reason": $reason }'
exit 0
