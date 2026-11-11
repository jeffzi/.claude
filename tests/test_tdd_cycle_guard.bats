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
		"git commit -m 'msg'"
}

@test "tdd cycle: other git subcommands are allowed while the marker is up" {
	each_allowed_in "$TDD_REPO" "git status"
}

# ── Targeted repository ──────────────────────────────────────────────────────

@test "named repo: an add aimed at a marked repo is blocked by its marker from an unmarked cwd" {
	each_blocked_in "$REPO" "git -C $TDD_REPO add README"
}

@test "named repo: a commit aimed at an unmarked repo from a marked cwd is allowed" {
	each_allowed_in "$TDD_REPO" "git -C $REPO commit -m 'msg'"
}

# ── Commands the rule never reads ────────────────────────────────────────────

@test "mention: a command that only mentions git add or git commit is allowed under the marker" {
	each_allowed_in "$TDD_REPO" \
		"echo git add docs/plans/x" \
		"rg 'git commit'" \
		"echo commit"
}
