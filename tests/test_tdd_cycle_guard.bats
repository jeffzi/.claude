#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export TDD_REPO
	TDD_REPO=$(setup_repo tdd_repo)
	touch "$(git -C "$TDD_REPO" rev-parse --absolute-git-dir)/tdd-cycle-active"

	export NO_REPO_DIR="$TMPDIR_ROOT/no_repo"
	mkdir -p "$NO_REPO_DIR"

	export ABSENT_REPO="$TMPDIR_ROOT/absent_repo"
}

teardown_file() {
	cleanup_tmpdir_root
}

# The marker path a block names, as the tail every spelling of the temp dir shares.
readonly MARKER_TAIL="tdd_repo/.git/tdd-cycle-active"

# Every command in the list is blocked from cwd $1 with output naming the
# marker; a failure names the command.
each_blocked_in() {
	local dir="$1"
	shift
	for_each_case run_tdd_cycle_guard "$dir" -- assert_blocked_with_reason "$MARKER_TAIL" -- "$@"
}

# Every command in the list is allowed from cwd $1; a failure names the command.
each_allowed_in() {
	local dir="$1"
	shift
	for_each_case run_tdd_cycle_guard "$dir" -- assert_allowed -- "$@"
}

# ── Marker up ────────────────────────────────────────────────────────────────

@test "tdd cycle: staging and committing are blocked naming the marker while it is up" {
	each_blocked_in "$TDD_REPO" \
		"git add README" \
		"git add ." \
		"git add -A" \
		"git commit -m 'msg'" \
		"git commit --amend"
}

@test "tdd cycle: other git subcommands are allowed while the marker is up" {
	each_allowed_in "$TDD_REPO" \
		"git status" \
		"git diff --cached"
}

@test "tdd cycle: staging and committing are allowed with no marker" {
	each_allowed_in "$REPO" \
		"git add README" \
		"git commit -m 'msg'"
}

# ── Targeted repository ──────────────────────────────────────────────────────

@test "named repo: add and commit aimed at a marked repo are blocked by its marker from an unmarked cwd" {
	each_blocked_in "$REPO" \
		"git -C $TDD_REPO add README" \
		"cd $TDD_REPO && git commit -m 'msg'" \
		"git --git-dir=$TDD_REPO/.git commit -m 'msg'" \
		"git --git-dir $TDD_REPO/.git commit -m 'msg'"
}

@test "named repo: commit aimed at a marked repo from outside any repository is blocked by its marker" {
	each_blocked_in "$NO_REPO_DIR" "git -C $TDD_REPO commit -m 'msg'"
}

@test "named repo: add and commit aimed at an unmarked repo from a marked cwd are allowed" {
	each_allowed_in "$TDD_REPO" \
		"git -C $REPO commit -m 'msg'" \
		"cd $REPO && git add README" \
		"git --git-dir=$REPO/.git commit -m 'msg'"
}

# ── Commands the rule never reads ────────────────────────────────────────────

@test "mention: a command that only mentions git add or git commit is allowed under the marker" {
	each_allowed_in "$TDD_REPO" \
		"echo git add docs/plans/x" \
		"rg 'git commit'" \
		"echo commit"
}

@test "no repo: commit outside any repository is allowed" {
	each_allowed_in "$NO_REPO_DIR" "git commit -m 'msg'"
}

@test "no repo: add and commit whose git dir is unknown never read the cwd's marker" {
	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	each_allowed_in "$TDD_REPO" \
		'git -C "$d" commit -m msg' \
		"git -C $ABSENT_REPO commit -m 'msg'" \
		"git --git-dir=$ABSENT_REPO/.git add README"
}

@test "unparseable: a command that does not parse is allowed under the marker" {
	run_tdd_cycle_guard "$TDD_REPO" 'git commit -m "unterminated'

	assert_allowed
}

# ── Helper failures ──────────────────────────────────────────────────────────

@test "helper failure: an ils parse failure blocks with its reason, even for a command with no git word" {
	local bin
	bin=$(failing_ils_bin "$TMPDIR_ROOT/broken_ils" 42)

	run_tdd_cycle_guard "$REPO" "echo hi" "$bin:$PATH"

	assert_blocked_with_reason "42"
}

@test "helper failure: jq missing from PATH blocks naming jq" {
	run_tdd_cycle_guard "$REPO" "echo hi" "$(path_without jq)"

	assert_blocked_with_reason "jq"
}
