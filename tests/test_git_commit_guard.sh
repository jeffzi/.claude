#!/usr/bin/env bash
set -euo pipefail

HOOK="$HOME/.claude/hooks/git-commit-guard.sh"
PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

hook_input() {
	jq -n --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

run_hook() {
	local cmd="$1"
	local exit_code=0
	local output
	output=$(hook_input "$cmd" | bash "$HOOK" 2>&1) || exit_code=$?
	printf '%d\t%s' "$exit_code" "$output"
}

expect_block() {
	local desc="$1"
	local cmd="$2"
	local result exit_code
	result=$(run_hook "$cmd")
	exit_code="${result%%	*}"
	if [[ "$exit_code" -eq 2 ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (exit %d, expected 2)\n" "$desc" "$exit_code"
		((++FAIL))
	fi
}

expect_allow() {
	local desc="$1"
	local cmd="$2"
	local result exit_code
	result=$(run_hook "$cmd")
	exit_code="${result%%	*}"
	if [[ "$exit_code" -eq 0 ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		local output="${result#*	}"
		printf "FAIL  %s  (exit %d, expected 0)\n    output: %s\n" "$desc" "$exit_code" "$output"
		((++FAIL))
	fi
}

# ── Numeric phase ID scopes ──────────────────────────────────────────────────

printf "\n── Numeric phase ID scopes ──────────────────────────────────────────────────\n"
expect_block "feat(05-01): ..." 'git commit -m "feat(05-01): add layout transitions"'
expect_block "test(03.5-01): ..." 'git commit -m "test(03.5-01): add fixtures"'
expect_block "docs(04.1-03): ..." 'git commit -m "docs(04.1-03): update docs"'
expect_block "fix(1-2): ..." 'git commit -m "fix(1-2): fix rendering"'

# ── Phase slug scopes ────────────────────────────────────────────────────────

printf "\n── Phase slug scopes ────────────────────────────────────────────────────────\n"
expect_block "test(05-layout-transitions-hud): ..." 'git commit -m "test(05-layout-transitions-hud): add tests"'
expect_block "feat(03-auth-middleware): ..." 'git commit -m "feat(03-auth-middleware): implement auth"'
expect_block "fix(12-data-pipeline): ..." 'git commit -m "fix(12-data-pipeline): fix ingestion"'

# ── TDD labels ────────────────────────────────────────────────────────────────

printf "\n── TDD labels ──────────────────────────────────────────────────────────────\n"
expect_block "RED-GREEN label" 'git commit -m "test: RED-GREEN cycle for auth"'
expect_block "TDD RED label" 'git commit -m "test: TDD RED phase for login"'
expect_block "GREEN phase label" 'git commit -m "feat: GREEN phase implementation"'

# ── .planning/ paths ─────────────────────────────────────────────────────────

printf "\n── .planning/ paths ─────────────────────────────────────────────────────────\n"
expect_block ".planning/ in message" 'git commit -m "docs: update .planning/phases/05/SUMMARY.md"'

# ── SUMMARY files ─────────────────────────────────────────────────────────────

printf "\n── SUMMARY files ────────────────────────────────────────────────────────────\n"
expect_block "05-01-SUMMARY.md" 'git commit -m "docs: complete 05-01-SUMMARY.md"'
expect_block "04.1-03-SUMMARY.md ref" 'git commit -m "docs(04): update 04-03-SUMMARY.md references"'

# ── Heredoc commits ──────────────────────────────────────────────────────────

printf "\n── Heredoc commits (regression: sed extraction used to miss these) ─────────\n"
expect_block "heredoc with phase ID" "$(printf 'git commit -F - <<EOF\nfeat(05-01): add layout\n\nBody text\nEOF')"
expect_block "heredoc with slug" "$(printf 'git commit -F - <<EOF\ntest(05-layout-transitions): tests\nEOF')"

# ── Clean commits (must not block) ───────────────────────────────────────────

printf "\n── Clean commits (must not block) ───────────────────────────────────────────\n"
expect_allow "normal feat" 'git commit -m "feat(auth): add login flow"'
expect_allow "normal fix" 'git commit -m "fix(api): reject empty email"'
expect_allow "normal refactor" 'git commit -m "refactor(parser): extract token stream"'
expect_allow "no scope" 'git commit -m "docs: update README"'
expect_allow "scope with dash" 'git commit -m "feat(net-http): add timeout"'
expect_allow "scope with slash" 'git commit -m "fix(net/http): handle redirects"'
expect_allow "single digit scope" 'git commit -m "fix(v2): patch endpoint"'
expect_allow "non-git command" 'echo "feat(05-01): not a commit"'

# ── Summary ──────────────────────────────────────────────────────────────────

printf "\n─────────────────────────────────────────────────────────────────────────────\n"
printf "%d passed, %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
