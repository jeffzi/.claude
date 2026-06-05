#!/usr/bin/env bash
set -euo pipefail

# git-commit-guard.sh — PreToolUse hook: blocks git commit messages that
# contain internal tooling references (plan IDs, TDD process labels, internal paths).

command -v jq >/dev/null || exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[[ -n "$cmd" ]] || exit 0
[[ "$cmd" =~ git[[:space:]].*commit ]] || exit 0

# Scan the full command — covers -m "...", --message=, heredocs, and -F input.
# Previous approach extracted only -m "..." which silently missed heredoc commits.
reason=""

# Numeric phase ID as scope: feat(03.5-01): or feat(05-01):
if printf '%s' "$cmd" | grep -qE '\([0-9]+\.?[0-9]*-[0-9]+\)'; then
	reason="Commit scope contains an internal phase ID (e.g. 05-01). Use a module name instead."
# Phase slug as scope: feat(05-layout-transitions-hud):
elif printf '%s' "$cmd" | grep -qE '\([0-9]{2,}-[a-z][a-z-]*\)'; then
	reason="Commit scope contains a phase slug (e.g. 05-layout-transitions). Use a module name instead."
# TDD cycle labels
elif printf '%s' "$cmd" | grep -qiE '(RED-GREEN|TDD RED|TDD GREEN|RED phase|GREEN phase|REFACTOR phase)'; then
	reason="Commit message contains a TDD process label. Describe what was built, not the cycle."
# Internal .planning/ path references
elif printf '%s' "$cmd" | grep -q '\.planning/'; then
	reason="Commit message references an internal .planning/ path."
# Phase-numbered SUMMARY files: 05-01-SUMMARY.md
elif printf '%s' "$cmd" | grep -qE '[0-9]{2,}-[0-9]+-SUMMARY\.md'; then
	reason="Commit message references an internal SUMMARY file. Describe the effect instead."
fi

if [[ -n "$reason" ]]; then
	jq -n --arg r "BLOCKED: $reason" '{ "decision": "block", "reason": $r }'
	exit 2
fi

exit 0
