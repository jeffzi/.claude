#!/usr/bin/env bats

load helpers/hooks

# Every command in the list is blocked with the reason $1; a failure names the
# command that broke the run.
each_blocked() {
	local reason="$1"
	shift
	for_each_case run_commit_guard -- assert_blocked_with_reason "$reason" -- "$@"
}

# Every command in the list is allowed; a failure names the command.
each_allowed() {
	for_each_case run_commit_guard -- assert_allowed -- "$@"
}

# ── Forbidden patterns in the command text ───────────────────────────────────

@test "numeric phase: a phase ID scope, whole or decimal, is blocked as an internal phase ID" {
	each_blocked "internal phase ID" \
		'git commit -m "feat(05-01): add layout transitions"' \
		'git commit -m "test(03.5-01): add fixtures"'
}

@test "phase slug: a numbered slug scope is blocked as a phase slug" {
	each_blocked "phase slug" \
		'git commit -m "feat(03-auth-middleware): implement auth"'
}

@test "TDD label: every cycle-phase label is blocked as a process label" {
	each_blocked "TDD process label" \
		'git commit -m "test: RED-GREEN cycle for auth"' \
		'git commit -m "test: TDD RED phase for login"' \
		'git commit -m "feat: GREEN phase implementation"'
}

@test "planning path: a .planning/ path in the message is blocked as an internal path" {
	each_blocked "internal .planning/ path" \
		'git commit -m "docs: update .planning/phases/05/SUMMARY.md"'
}

@test "summary file: a SUMMARY file name in subject or body is blocked as an internal file" {
	each_blocked "internal SUMMARY file" \
		'git commit -m "docs: complete 05-01-SUMMARY.md"' \
		'git commit -m "docs(04): update 04-03-SUMMARY.md references"'
}

@test "heredoc: a phase ID inside a -F - heredoc body is blocked" {
	each_blocked "internal phase ID" \
		"$(printf 'git commit -F - <<EOF\nfeat(05-01): add layout\n\nBody text\nEOF')"
}

# ── Clean commits (must not block) ───────────────────────────────────────────

@test "clean: a message matching no pattern is allowed" {
	each_allowed \
		'git commit -m "feat(auth): add login flow"' \
		'git commit -m "docs: update README"' \
		'git commit -m "fix(net/http): handle redirects"'
}

@test "clean: scopes that nearly match a phase pattern are allowed" {
	each_allowed \
		'git commit -m "feat(net-http): add timeout"' \
		'git commit -m "fix(v2): patch endpoint"'
}

@test "clean: a non-git command carrying a phase ID is allowed" {
	each_allowed 'echo "feat(05-01): not a commit"'
}

# ── Message files (-F/--file) ────────────────────────────────────────────────

# Prints the path on stdout so callers can interpolate it into the git command under test.
write_planning_msg_file() {
	local msg="$BATS_TEST_TMPDIR/planning.txt"
	printf 'docs: update notes\n\nSee .planning/plan-x.md for the rollout.\n' >"$msg"
	printf '%s' "$msg"
}

@test "message file: every flag spelling reads the file and blocks on its .planning/ reference" {
	local msg
	msg=$(write_planning_msg_file)

	each_blocked "internal .planning/ path" \
		"git commit -F $msg" \
		"git commit --file $msg" \
		"git commit --file=$msg"
}

@test "message file: a quoted path is unwrapped before the file is read" {
	local msg
	msg=$(write_planning_msg_file)

	each_blocked "internal .planning/ path" \
		"git commit -F \"$msg\"" \
		"git commit --file='$msg'" \
		"git commit --file=\"$msg\""
}

@test "message file: clean message file is allowed" {
	local msg="$BATS_TEST_TMPDIR/clean.txt"
	printf 'feat(auth): add login flow\n\nSupports the password grant.\n' >"$msg"

	run_commit_guard "git commit -F $msg"

	assert_allowed
}

@test "message file: missing path is allowed" {
	run_commit_guard "git commit -F $BATS_TEST_TMPDIR/absent.txt"

	assert_allowed
}

@test "message file: -F - reading stdin is allowed" {
	run_commit_guard 'git commit -F -'

	assert_allowed
}

@test "message file: command-text match blocks with a clean -F file" {
	local msg="$BATS_TEST_TMPDIR/.planning/msg.txt"
	mkdir -p "$BATS_TEST_TMPDIR/.planning"
	printf 'feat(auth): add login flow\n' >"$msg"

	run_commit_guard "git commit -F $msg"

	assert_blocked
	assert_guard_output_includes "internal .planning/ path"
}

# ── Pull request title and body (gh pr create/edit) ──────────────────────────

@test "pull request: a phase ID in the title, body, or a heredoc of gh pr create or edit is blocked" {
	# shellcheck disable=SC2016 # the literal $(...) is the command text under test
	each_blocked "internal phase ID" \
		'gh pr create --title "feat(05-01): add layout" --body "Adds the layout."' \
		'gh pr create -t "feat(05-01): add layout" -b "Adds the layout."' \
		'gh pr create --title "Add layout" --body "Follows feat(05-01): add layout."' \
		'gh pr edit 12 --title "feat(05-01): add layout"' \
		'gh pr edit 12 -b "Follows feat(05-01): add layout."' \
		"$(printf 'gh pr create --title "Add layout" --body-file - <<EOF\nfeat(05-01): add layout\n\nBody text\nEOF')" \
		"$(printf 'gh pr edit 12 --body "$(cat <<EOF\nfeat(05-01): add layout\nEOF\n)"')"
}

@test "pull request: every body-file spelling reads the file and blocks on its .planning/ reference" {
	local msg
	msg=$(write_planning_msg_file)

	each_blocked "internal .planning/ path" \
		"gh pr create --title \"Add layout\" -F $msg" \
		"gh pr create --title \"Add layout\" --body-file $msg" \
		"gh pr create --title \"Add layout\" --body-file=$msg" \
		"gh pr edit 12 -F \"$msg\"" \
		"gh pr edit 12 --body-file='$msg'" \
		"gh pr edit 12 --body-file=\"$msg\""
}

@test "pull request: a clean, missing, or stdin body file is allowed" {
	local clean="$BATS_TEST_TMPDIR/clean.txt"
	printf 'Adds the login flow.\n\nSupports the password grant.\n' >"$clean"

	each_allowed \
		"gh pr create --title \"feat(auth): add login flow\" --body-file $clean" \
		"gh pr edit 12 -F $BATS_TEST_TMPDIR/absent.txt" \
		'gh pr create --title "feat(auth): add login flow" -F -'
}

@test "pull request: a clean gh pr create or edit is allowed" {
	each_allowed \
		'gh pr create --title "feat(auth): add login flow" --body "Supports the password grant."' \
		'gh pr edit 12 -t "fix(net/http): handle redirects" -b "Follows redirects."'
}

@test "pull request: other gh commands carrying a pattern are allowed" {
	each_allowed \
		'gh pr view 12 --json title --jq ".title == \"feat(05-01): add layout\""' \
		'gh issue create --title "feat(05-01): add layout" --body "Tracks the layout."' \
		'gh pr comment 12 --body "See .planning/notes.md"'
}
