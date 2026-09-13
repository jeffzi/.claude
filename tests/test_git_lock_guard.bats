#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export GIT_LOCK_GUARD_TIMEOUT_MS=200

	export REPO
	REPO=$(setup_repo repo)

	export LOCKED_REPO
	LOCKED_REPO=$(setup_repo locked_repo)
	touch "$(git -C "$LOCKED_REPO" rev-parse --absolute-git-dir)/index.lock"

	export NO_REPO_DIR="$TMPDIR_ROOT/no_repo"
	mkdir -p "$NO_REPO_DIR"
}

teardown_file() {
	cleanup_tmpdir_root
}

@test "named repo: commit -C at a locked repo from an unlocked cwd waits and names that repo's lock" {
	run_lock_guard "$REPO" "git -C $LOCKED_REPO commit -m 'msg'"

	assert_blocked
	assert_guard_output_includes "locked_repo/.git/index.lock"
}

@test "named repo: commit -C at a locked repo from outside any repo waits and names that repo's lock" {
	run_lock_guard "$NO_REPO_DIR" "git -C $LOCKED_REPO commit -m 'msg'"

	assert_blocked
	assert_guard_output_includes "locked_repo/.git/index.lock"
}

@test "named repo: commit -C at an unlocked repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git -C $REPO commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

@test "named repo: commit -C at a path that is no repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git -C $TMPDIR_ROOT/absent commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

@test "named repo: commit --git-dir at a path that is no repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git --git-dir=$TMPDIR_ROOT/absent/.git commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

@test "named repo: commit with a separate --git-dir word at a path that is no repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git --git-dir $TMPDIR_ROOT/absent/.git commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}
