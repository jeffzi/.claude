#!/usr/bin/env bats

load helpers/hooks

# A commit or pull request message whose body names a .planning/ path.
readonly PLANNING_MSG=$'docs: update notes\n\nSee .planning/plan-x.md for the rollout.\n'

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

@test "TDD label: a cycle-phase label is blocked as a process label" {
	each_blocked "TDD process label" 'git commit -m "test: RED-GREEN cycle for auth"'
}

@test "planning path: a .planning/ path in the message is blocked as an internal path" {
	each_blocked "internal .planning/ path" \
		'git commit -m "docs: update .planning/phases/05/SUMMARY.md"'
}

@test "summary file: a SUMMARY file name in subject or body is blocked as an internal file" {
	each_blocked "internal SUMMARY file" \
		'git commit -m "docs: complete 05-01-SUMMARY.md"' \
		'git commit -m "docs: update notes" -m "See 04-03-SUMMARY.md"'
}

# ── Clean commits (must not block) ───────────────────────────────────────────

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
	printf '%s' "$PLANNING_MSG" >"$msg"
	printf '%s' "$msg"
}

@test "message file: every flag spelling reads the file and blocks on its .planning/ reference" {
	local msg
	msg=$(write_planning_msg_file)

	each_blocked "internal .planning/ path" \
		"git commit -F $msg" \
		"git commit --file=$msg"
}

@test "message file: command-text match blocks with a clean -F file" {
	local msg="$BATS_TEST_TMPDIR/.planning/msg.txt"
	mkdir -p "$BATS_TEST_TMPDIR/.planning"
	printf 'feat(auth): add login flow\n' >"$msg"

	run_commit_guard "git commit -F $msg"

	assert_blocked_with_reason "internal .planning/ path"
}

# ── Pull request title and body (gh pr create/edit) ──────────────────────────

@test "pull request: a phase ID in the title of gh pr create is blocked" {
	each_blocked "internal phase ID" \
		'gh pr create --title "feat(05-01): add layout" --body "Adds the layout."'
}

@test "pull request: a phase ID in the body of gh pr edit is blocked" {
	each_blocked "internal phase ID" \
		'gh pr edit 12 -b "Follows feat(05-01): add layout."'
}

@test "pull request: other gh commands carrying a pattern are allowed" {
	each_allowed \
		'gh pr view 12 --json title --jq ".title == \"feat(05-01): add layout\""' \
		'gh issue create --title "feat(05-01): add layout" --body "Tracks the layout."'
}

# ── Which invocations are scanned ────────────────────────────────────────────

@test "both: a commit and a pull request in one command each have their message file scanned" {
	local planning clean="$BATS_TEST_TMPDIR/clean.txt"
	planning=$(write_planning_msg_file)
	printf 'feat(auth): add login flow\n' >"$clean"

	each_blocked "internal .planning/ path" \
		"git commit -F $planning && gh pr create --title 'Add layout' -F $clean" \
		"git commit -F $clean && gh pr create --title 'Add layout' --body-file $planning"
}

# ── Message file resolution ──────────────────────────────────────────────────

@test "message file: a relative path resolves against the directory the invocation runs in" {
	local dir="$BATS_TEST_TMPDIR/sub"
	mkdir -p "$dir"
	printf '%s' "$PLANNING_MSG" >"$dir/msg.txt"

	each_blocked "internal .planning/ path" \
		"cd $dir && git commit -F msg.txt"
}

@test "pull request: a body file given as -F=, a -F= cluster, or after a no-value cluster is scanned" {
	printf 'Follows feat(05-01): add layout.\n' >"$BATS_TEST_TMPDIR/body.md"

	each_blocked "internal phase ID" \
		"gh pr create --title 'Add layout' -F=body.md" \
		"gh pr create --title 'Add layout' -dF=body.md" \
		"gh pr create --title 'Add layout' -eF body.md"
}

@test "pull request: a clean body file given as -F= is allowed beside a dirty =body.md" {
	printf 'Adds the layout.\n' >"$BATS_TEST_TMPDIR/body.md"
	printf 'Follows feat(05-01): add layout.\n' >"$BATS_TEST_TMPDIR/=body.md"

	each_allowed \
		"gh pr create --title 'Add layout' -F=body.md" \
		"gh pr create --title 'Add layout' -dF=body.md" \
		"gh pr create --title 'Add layout' -eF body.md"
}

@test "message file: git commit -F= reads the file named with its leading =" {
	printf 'Follows feat(05-01): add layout.\n' >"$BATS_TEST_TMPDIR/=msg.txt"

	each_blocked "internal phase ID" 'git commit -F=msg.txt'
}

@test "message file: git commit -F= ignores a dirty file named without the leading =" {
	printf 'Follows feat(05-01): add layout.\n' >"$BATS_TEST_TMPDIR/msg.txt"
	printf 'Adds the layout.\n' >"$BATS_TEST_TMPDIR/=msg.txt"

	each_allowed 'git commit -F=msg.txt'
}

@test "message file: a file named - in the cwd is never read for -F -" {
	printf '%s' "$PLANNING_MSG" >"$BATS_TEST_TMPDIR/-"

	each_allowed 'git commit -F -'
}
