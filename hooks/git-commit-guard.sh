#!/usr/bin/env bash
set -euo pipefail

# git-commit-guard.sh — PreToolUse hook: blocks git commit messages that
# contain internal tooling references (plan IDs, TDD process labels, internal paths).

command -v jq >/dev/null || exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[[ -n "$cmd" ]] || exit 0
[[ "$cmd" =~ git[[:space:]].*commit ]] || exit 0

# Each check pairs a grep invocation (flags + pattern) with its block reason.
check_flags=(-qE -qE -qiE -qE -qE)
check_patterns=(
	'\([0-9]+\.?[0-9]*-[0-9]+\)'
	'\([0-9]{2,}-[a-z][a-z-]*\)'
	'(RED-GREEN|TDD RED|TDD GREEN|RED phase|GREEN phase|REFACTOR phase)'
	'\.planning/'
	'[0-9]{2,}-[0-9]+-SUMMARY\.md'
)
check_reasons=(
	"Commit scope contains an internal phase ID (e.g. 05-01). Use a module name instead."
	"Commit scope contains a phase slug (e.g. 05-layout-transitions). Use a module name instead."
	"Commit message contains a TDD process label. Describe what was built, not the cycle."
	"Commit message references an internal .planning/ path."
	"Commit message references an internal SUMMARY file. Describe the effect instead."
)

# Print the reason of the first check matching $1; print nothing when it is clean.
scan_text() {
	local text="$1" i
	for i in "${!check_patterns[@]}"; do
		if printf '%s' "$text" | grep "${check_flags[$i]}" "${check_patterns[$i]}"; then
			printf '%s' "${check_reasons[$i]}"
			return 0
		fi
	done
	return 0
}

# Print the path given to -F/--file/--file= in $1; nothing when the flag is absent.
# The path may be quoted in the command text; the quotes are shell syntax, not
# part of the path, so a quoted span is matched whole and unwrapped.
message_file_path() {
	local text="$1" path
	local flag_re="(^|[[:space:]])(-F|--file)([[:space:]]+|=)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)"
	[[ "$text" =~ $flag_re ]] || return 0
	path="${BASH_REMATCH[4]}"
	if [[ "$path" == '"'*'"' || "$path" == "'"*"'" ]]; then
		path="${path:1:${#path}-2}"
	fi
	printf '%s' "$path"
}

# Do not extract only -m "...": heredoc and -F commits would be missed.
reason=$(scan_text "$cmd")

# A -F/--file commit keeps the message out of the command text, so scan the file
# too. "-" is stdin, already covered by the command-text scan of the heredoc.
if [[ -z "$reason" ]]; then
	message_file=$(message_file_path "$cmd")
	if [[ -n "$message_file" && "$message_file" != "-" && -f "$message_file" && -r "$message_file" ]]; then
		reason=$(scan_text "$(cat -- "$message_file")")
	fi
fi

if [[ -n "$reason" ]]; then
	jq -n --arg r "BLOCKED: $reason" '{ "decision": "block", "reason": $r }'
	exit 2
fi

exit 0
