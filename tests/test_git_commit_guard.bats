#!/usr/bin/env bats

load helpers/hooks

# ── Numeric phase ID scopes ──────────────────────────────────────────────────

@test "numeric phase: feat(05-01): ... is blocked" {
	run_commit_guard 'git commit -m "feat(05-01): add layout transitions"'
	assert_blocked
}

@test "numeric phase: test(03.5-01): ... is blocked" {
	run_commit_guard 'git commit -m "test(03.5-01): add fixtures"'
	assert_blocked
}

@test "numeric phase: docs(04.1-03): ... is blocked" {
	run_commit_guard 'git commit -m "docs(04.1-03): update docs"'
	assert_blocked
}

@test "numeric phase: fix(1-2): ... is blocked" {
	run_commit_guard 'git commit -m "fix(1-2): fix rendering"'
	assert_blocked
}

# ── Phase slug scopes ────────────────────────────────────────────────────────

@test "phase slug: test(05-layout-transitions-hud): ... is blocked" {
	run_commit_guard 'git commit -m "test(05-layout-transitions-hud): add tests"'
	assert_blocked
}

@test "phase slug: feat(03-auth-middleware): ... is blocked" {
	run_commit_guard 'git commit -m "feat(03-auth-middleware): implement auth"'
	assert_blocked
}

@test "phase slug: fix(12-data-pipeline): ... is blocked" {
	run_commit_guard 'git commit -m "fix(12-data-pipeline): fix ingestion"'
	assert_blocked
}

# ── TDD labels ───────────────────────────────────────────────────────────────

@test "TDD label: RED-GREEN label is blocked" {
	run_commit_guard 'git commit -m "test: RED-GREEN cycle for auth"'
	assert_blocked
}

@test "TDD label: TDD RED label is blocked" {
	run_commit_guard 'git commit -m "test: TDD RED phase for login"'
	assert_blocked
}

@test "TDD label: GREEN phase label is blocked" {
	run_commit_guard 'git commit -m "feat: GREEN phase implementation"'
	assert_blocked
}

# ── .planning/ paths ─────────────────────────────────────────────────────────

@test "planning path: .planning/ in message is blocked" {
	run_commit_guard 'git commit -m "docs: update .planning/phases/05/SUMMARY.md"'
	assert_blocked
}

# ── SUMMARY files ────────────────────────────────────────────────────────────

@test "summary file: 05-01-SUMMARY.md is blocked" {
	run_commit_guard 'git commit -m "docs: complete 05-01-SUMMARY.md"'
	assert_blocked
}

@test "summary file: 04.1-03-SUMMARY.md ref is blocked" {
	run_commit_guard 'git commit -m "docs(04): update 04-03-SUMMARY.md references"'
	assert_blocked
}

# ── Heredoc commits ─────────────────────────────────────────────────────────

@test "heredoc: heredoc with phase ID is blocked" {
	run_commit_guard "$(printf 'git commit -F - <<EOF\nfeat(05-01): add layout\n\nBody text\nEOF')"
	assert_blocked
}

@test "heredoc: heredoc with slug is blocked" {
	run_commit_guard "$(printf 'git commit -F - <<EOF\ntest(05-layout-transitions): tests\nEOF')"
	assert_blocked
}

# ── Clean commits (must not block) ───────────────────────────────────────────

@test "clean: normal feat is allowed" {
	run_commit_guard 'git commit -m "feat(auth): add login flow"'
	assert_allowed
}

@test "clean: normal fix is allowed" {
	run_commit_guard 'git commit -m "fix(api): reject empty email"'
	assert_allowed
}

@test "clean: normal refactor is allowed" {
	run_commit_guard 'git commit -m "refactor(parser): extract token stream"'
	assert_allowed
}

@test "clean: no scope is allowed" {
	run_commit_guard 'git commit -m "docs: update README"'
	assert_allowed
}

@test "clean: scope with dash is allowed" {
	run_commit_guard 'git commit -m "feat(net-http): add timeout"'
	assert_allowed
}

@test "clean: scope with slash is allowed" {
	run_commit_guard 'git commit -m "fix(net/http): handle redirects"'
	assert_allowed
}

@test "clean: single digit scope is allowed" {
	run_commit_guard 'git commit -m "fix(v2): patch endpoint"'
	assert_allowed
}

@test "clean: non-git command is allowed" {
	run_commit_guard 'echo "feat(05-01): not a commit"'
	assert_allowed
}
