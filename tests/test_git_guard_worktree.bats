#!/usr/bin/env bats

load helpers/hooks
load helpers/guard

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export WT_REPO
	WT_REPO=$(setup_repo wt_repo)

	export CLEAN_WT
	CLEAN_WT=$(add_worktree "$WT_REPO" clean)

	export DIRTY_WT
	DIRTY_WT=$(add_worktree "$WT_REPO" dirty)
	printf 'uncommitted\n' >>"$DIRTY_WT/README"

	export WT_GLOB_REPO
	WT_GLOB_REPO=$(setup_repo wt_glob_repo)
	git -C "$WT_GLOB_REPO" worktree add -q -b wt-glob "$WT_GLOB_REPO/wt1"
	printf 'uncommitted\n' >>"$WT_GLOB_REPO/wt1/README"

	export WT_NAMED_DIRTY_REPO
	WT_NAMED_DIRTY_REPO=$(setup_repo wt_named_dirty_repo)
	git -C "$WT_NAMED_DIRTY_REPO" worktree add -q -b wt-named "$WT_NAMED_DIRTY_REPO/wt1"
	printf 'uncommitted\n' >>"$WT_NAMED_DIRTY_REPO/wt1/README"

	export WT_NAMED_CLEAN_REPO
	WT_NAMED_CLEAN_REPO=$(setup_repo wt_named_clean_repo)
	git -C "$WT_NAMED_CLEAN_REPO" worktree add -q -b wt-named "$WT_NAMED_CLEAN_REPO/wt1"
}

teardown_file() {
	cleanup_tmpdir_root
}

# ── Worktree ─────────────────────────────────────────────────────────────────

@test "worktree: remove of a clean worktree is allowed" {
	run_guard "$WT_REPO" "git worktree remove $CLEAN_WT"

	assert_allowed
}

@test "worktree: remove of a dirty worktree is blocked" {
	run_guard "$WT_REPO" "git worktree remove $DIRTY_WT"

	assert_blocked
}

@test "worktree: remove --force of a clean worktree is blocked" {
	run_guard "$WT_REPO" "git worktree remove --force $CLEAN_WT"

	assert_blocked
}

@test "worktree: remove with a short force flag, alone or bundled, is blocked" {
	each_blocked_in "$WT_REPO" \
		"git worktree remove -f $CLEAN_WT" \
		"git worktree remove -fv $CLEAN_WT"
}

@test "worktree: remove of a path the guard cannot verify is blocked" {
	# shellcheck disable=SC2016
	each_blocked_in "$WT_REPO" \
		'git worktree remove "$wt"' \
		"git worktree remove" \
		"git worktree remove $TMPDIR_ROOT/absent"
}

@test "worktree: remove --force in a for loop over quoted paths is blocked" {
	# shellcheck disable=SC2016
	run_guard "$WT_REPO" 'for wt in .claude/worktrees/a .claude/worktrees/b; do git worktree unlock "$wt" 2>/dev/null; git worktree remove --force "$wt"; done'

	assert_blocked
}

@test "worktree: remove -C of a relative path to a dirty worktree in the named repo is blocked as dirty" {
	run_guard "$REPO" "git -C $WT_NAMED_DIRTY_REPO worktree remove wt1"

	assert_blocked
	assert_guard_output_includes "worktree remove (dirty)"
}

@test "worktree: remove -C of a relative path to a clean worktree in the named repo is allowed from a cwd holding a dirty one" {
	run_guard "$WT_GLOB_REPO" "git -C $WT_NAMED_CLEAN_REPO worktree remove wt1"

	assert_allowed
}

@test "worktree: remove -C of a relative path absent from the named repo is unverifiable even when the cwd holds it" {
	run_guard "$WT_NAMED_CLEAN_REPO" "git -C $REPO worktree remove wt1"

	assert_blocked
	assert_guard_output_includes "unverifiable path"
}

@test "worktree: remove -C of an absolute path to a clean worktree is allowed" {
	run_guard "$REPO" "git -C $WT_REPO worktree remove $CLEAN_WT"

	assert_allowed
}

@test "worktree: remove of a relative path to a clean worktree without -C is allowed" {
	run_guard "$WT_REPO" "git worktree remove .claude/worktrees/clean"

	assert_allowed
}

@test "worktree: remove of a relative path behind relative or chained -C values resolves the way git does" {
	each_blocked_for_in "worktree remove (dirty)" "$TMPDIR_ROOT" \
		"git -C wt_named_dirty_repo worktree remove wt1"
	each_blocked_for_in "worktree remove (dirty)" "$REPO" \
		"git -C $TMPDIR_ROOT -C wt_named_dirty_repo worktree remove wt1" \
		"git -C wt_named_clean_repo -C $WT_NAMED_DIRTY_REPO worktree remove wt1" \
		"git -C $TMPDIR_ROOT --git-dir elsewhere/.git -C wt_named_dirty_repo worktree remove wt1"
}

@test "worktree: list, add, unlock, and prune are allowed" {
	# shellcheck disable=SC2016
	each_allowed_in "$WT_REPO" \
		"git worktree list" \
		"git worktree add $TMPDIR_ROOT/added-wt" \
		'git worktree unlock "$wt"' \
		"git worktree prune"
}
