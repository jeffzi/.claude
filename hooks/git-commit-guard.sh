#!/usr/bin/env bash
set -euo pipefail

# git-commit-guard.sh — PreToolUse hook: blocks git commit messages that
# contain internal tooling references (plan IDs, TDD process labels, internal paths).

command -v jq >/dev/null || exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[[ -n "$cmd" ]] || exit 0
[[ "$cmd" =~ git[[:space:]].*commit ]] || exit 0

# Do not extract only -m "...": heredoc and -F commits would be missed.
reason=""

# Each check pairs a grep invocation (flags + pattern) with its block reason.
# Numeric phase ID (03.5-01, 05-01) / phase slug / TDD labels / .planning/ path / SUMMARY file.
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

for i in "${!check_patterns[@]}"; do
	if printf '%s' "$cmd" | grep "${check_flags[$i]}" "${check_patterns[$i]}"; then
		reason="${check_reasons[$i]}"
		break
	fi
done

if [[ -n "$reason" ]]; then
	jq -n --arg r "BLOCKED: $reason" '{ "decision": "block", "reason": $r }'
	exit 2
fi

exit 0
