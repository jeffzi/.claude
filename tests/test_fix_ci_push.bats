#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export NO_MARKER
	NO_MARKER=$(setup_pair no_marker)

	export STALE
	STALE=$(setup_marked_pair stale)
	backdate_marker "$STALE" "$STALE_OFFSET_MINUTES"

	export FUTURE
	FUTURE=$(setup_marked_pair future)
	backdate_marker "$FUTURE" "$FUTURE_OFFSET_MINUTES"

	export PLAIN
	PLAIN=$(setup_marked_pair plain)

	export UPSTREAM
	UPSTREAM=$(setup_marked_pair upstream)

	export OUTSIDE
	OUTSIDE=$(setup_marked_pair outside)

	export REFUSE
	REFUSE=$(setup_marked_pair refuse)
	add_branch "$REFUSE" feature
	seed_origin "$REFUSE" main feature

	export NO_MARKER_DELETE
	NO_MARKER_DELETE=$(setup_pair no_marker_delete)
	seed_origin "$NO_MARKER_DELETE" fix-ci/lint

	export DELETE_FLAG
	DELETE_FLAG=$(setup_marked_pair delete_flag)
	add_branch "$DELETE_FLAG" plan/x
	seed_origin "$DELETE_FLAG" main fix-ci/lint plan/x

	export DELETE_COLON
	DELETE_COLON=$(setup_marked_pair delete_colon)
	add_branch "$DELETE_COLON" plan/x
	seed_origin "$DELETE_COLON" main fix-ci/lint plan/x

	export SQUASHED
	SQUASHED=$(setup_marked_pair squashed)
	add_unmerged_branch "$SQUASHED" fix-ci/squashed
	seed_origin "$SQUASHED" fix-ci/squashed

	export NO_LOCAL
	NO_LOCAL=$(setup_marked_pair no_local)
	seed_origin "$NO_LOCAL" fix-ci/lint
	git -C "$NO_LOCAL" branch -q -D fix-ci/lint

	export REMOTE_FAIL
	REMOTE_FAIL=$(setup_marked_pair remote_fail)

	export CHECKED_OUT
	CHECKED_OUT=$(setup_marked_pair checked_out)
	seed_origin "$CHECKED_OUT" fix-ci/lint
	git -C "$CHECKED_OUT" switch -q fix-ci/lint

	export FULL_REF
	FULL_REF=$(setup_marked_pair full_ref)
	seed_origin "$FULL_REF" fix-ci/lint

	# fix-ci/lint is checked out; plan/x is not.
	export CHECKED_OUT_MIXED
	CHECKED_OUT_MIXED=$(setup_marked_pair checked_out_mixed)
	add_branch "$CHECKED_OUT_MIXED" plan/x
	seed_origin "$CHECKED_OUT_MIXED" fix-ci/lint plan/x
	git -C "$CHECKED_OUT_MIXED" switch -q fix-ci/lint

	export NOT_A_REPO
	NOT_A_REPO="$TMPDIR_ROOT/not_a_repo"
	mkdir -p "$NOT_A_REPO"
}

teardown_file() {
	[[ -n "$TMPDIR_ROOT" ]] && rm -rf "$TMPDIR_ROOT"
}

# ── Marker gate ──────────────────────────────────────────────────────────────

@test "marker gate: push without a marker is refused as no active loop" {
	run_wrapper "$NO_MARKER" origin fix-ci/lint

	assert_refused
	assert_reason "is absent"
	assert_ref_absent "$(bare_of "$NO_MARKER")" fix-ci/lint
}

@test "marker gate: push under a stale marker is refused as an ended loop" {
	run_wrapper "$STALE" origin fix-ci/lint

	assert_refused
	assert_reason "not from the last"
	assert_ref_absent "$(bare_of "$STALE")" fix-ci/lint
}

@test "marker gate: push under a future-dated marker is refused as an ended loop" {
	run_wrapper "$FUTURE" origin fix-ci/lint

	assert_refused
	assert_reason "not from the last"
	assert_ref_absent "$(bare_of "$FUTURE")" fix-ci/lint
}

@test "marker gate: a stat that answers neither dialect is named instead of reading as an ended loop" {
	local work bin
	work=$(setup_marked_pair nostat)
	bin=$(failing_stat_bin "$TMPDIR_ROOT/nostat")

	run_script_on_path "$work" "$bin:$PATH" "$FIX_CI_PUSH_WRAPPER" origin fix-ci/lint

	assert_run_failed 1
	assert_reason "marker age cannot be read"
	assert_ref_absent "$(bare_of "$work")" fix-ci/lint
}

# ── Pass-through under a fresh marker ────────────────────────────────────────

@test "pass-through: push of a fix-ci branch lands in origin" {
	run_wrapper "$PLAIN" origin fix-ci/lint

	assert_run_ok
	assert_ref_present "$(bare_of "$PLAIN")" fix-ci/lint
	assert_ref_present "$PLAIN" fix-ci/lint
}

@test "pass-through: push -u of a fix-ci branch lands in origin" {
	run_wrapper "$UPSTREAM" -u origin fix-ci/lint

	assert_run_ok
	assert_ref_present "$(bare_of "$UPSTREAM")" fix-ci/lint
	assert_ref_present "$UPSTREAM" fix-ci/lint
}

@test "pass-through: push of a branch outside both namespaces lands in origin" {
	run_wrapper "$OUTSIDE" origin main

	assert_run_ok
	assert_ref_present "$(bare_of "$OUTSIDE")" main
}

# ── Flag whitelist ───────────────────────────────────────────────────────────

@test "flag whitelist: every unlisted flag is refused naming the whitelist" {
	local flag
	for flag in -f --force-with-lease -fu --mirror; do
		run_wrapper "$REFUSE" "$flag" origin fix-ci/lint

		assert_refused || {
			printf 'flag: %s\n' "$flag" >&2
			return 1
		}
		assert_reason "is not allowed" || {
			printf 'flag: %s\n' "$flag" >&2
			return 1
		}
	done
	assert_ref_absent "$(bare_of "$REFUSE")" fix-ci/lint
}

@test "flag whitelist: a force refspec is refused as a history rewrite" {
	run_wrapper "$REFUSE" origin +main:main

	assert_refused
	assert_reason "forces the update"
}

@test "flag whitelist: a push naming no refspec is refused" {
	run_wrapper "$REFUSE" origin

	assert_refused
	assert_reason "no refspec named"
}

# ── Delete scoping ───────────────────────────────────────────────────────────

@test "marker gate: --delete without a marker leaves the branch in origin and locally" {
	run_wrapper "$NO_MARKER_DELETE" origin --delete fix-ci/lint

	assert_refused
	assert_ref_present "$(bare_of "$NO_MARKER_DELETE")" fix-ci/lint
	assert_ref_present "$NO_MARKER_DELETE" fix-ci/lint
}

@test "delete scope: push --delete main is refused naming both allowed namespaces" {
	run_wrapper "$REFUSE" origin --delete main

	assert_refused
	assert_reason "fix-ci/*"
	assert_reason "plan/*"
	assert_ref_present "$(bare_of "$REFUSE")" main
}

@test "delete scope: push :main (delete refspec) is refused naming both allowed namespaces" {
	run_wrapper "$REFUSE" origin :main

	assert_refused
	assert_reason "fix-ci/*"
	assert_reason "plan/*"
	assert_ref_present "$(bare_of "$REFUSE")" main
}

@test "delete scope: a --delete naming an outside branch after a fix-ci one deletes neither locally" {
	run_wrapper "$REFUSE" origin --delete fix-ci/lint feature

	assert_refused
	assert_ref_present "$(bare_of "$REFUSE")" feature
	assert_ref_present "$REFUSE" fix-ci/lint
	assert_ref_present "$REFUSE" feature
}

@test "delete scope: push --delete of a fix-ci and a plan branch removes both from origin and locally" {
	run_wrapper "$DELETE_FLAG" origin --delete fix-ci/lint plan/x

	assert_run_ok
	assert_ref_absent "$(bare_of "$DELETE_FLAG")" fix-ci/lint
	assert_ref_absent "$(bare_of "$DELETE_FLAG")" plan/x
	assert_ref_absent "$DELETE_FLAG" fix-ci/lint
	assert_ref_absent "$DELETE_FLAG" plan/x
}

@test "delete scope: delete refspecs for a fix-ci and a plan branch remove both from origin and locally" {
	run_wrapper "$DELETE_COLON" origin :fix-ci/lint :plan/x

	assert_run_ok
	assert_ref_absent "$(bare_of "$DELETE_COLON")" fix-ci/lint
	assert_ref_absent "$(bare_of "$DELETE_COLON")" plan/x
	assert_ref_absent "$DELETE_COLON" fix-ci/lint
	assert_ref_absent "$DELETE_COLON" plan/x
}

# ── Local cleanup after a remote delete ──────────────────────────────────────

@test "local cleanup: --delete removes a squash-merged fix-ci branch git branch -d would refuse" {
	run_wrapper "$SQUASHED" origin --delete fix-ci/squashed

	assert_run_ok
	assert_ref_absent "$(bare_of "$SQUASHED")" fix-ci/squashed
	assert_ref_absent "$SQUASHED" fix-ci/squashed
}

@test "local cleanup: --delete of a branch with no local copy still succeeds remotely" {
	run_wrapper "$NO_LOCAL" origin --delete fix-ci/lint

	assert_run_ok
	assert_ref_absent "$(bare_of "$NO_LOCAL")" fix-ci/lint
}

@test "local cleanup: a failed remote delete keeps the local branch" {
	run_wrapper "$REMOTE_FAIL" origin --delete fix-ci/lint

	assert_run_nonzero
	assert_ref_present "$REMOTE_FAIL" fix-ci/lint
}

@test "local cleanup: --delete of the checked-out branch keeps it locally and names it" {
	run_wrapper "$CHECKED_OUT" origin --delete fix-ci/lint

	assert_run_failed 2
	assert_reason "switch away from 'fix-ci/lint'"
	assert_ref_absent "$(bare_of "$CHECKED_OUT")" fix-ci/lint
	assert_ref_present "$CHECKED_OUT" fix-ci/lint
}

@test "local cleanup: --delete of a full refs/heads/ name removes the local branch too" {
	run_wrapper "$FULL_REF" origin --delete refs/heads/fix-ci/lint

	assert_run_ok
	assert_ref_absent "$(bare_of "$FULL_REF")" fix-ci/lint
	assert_ref_absent "$FULL_REF" fix-ci/lint
}

@test "local cleanup: a checked-out branch among several keeps only that one locally" {
	run_wrapper "$CHECKED_OUT_MIXED" origin --delete fix-ci/lint plan/x

	assert_run_failed 2
	assert_reason "switch away from 'fix-ci/lint'"
	assert_ref_present "$CHECKED_OUT_MIXED" fix-ci/lint
	assert_ref_absent "$CHECKED_OUT_MIXED" plan/x
}

# ── Diagnostics ──────────────────────────────────────────────────────────────

@test "diagnostics: git's own reason for an unusable repo" {
	run_wrapper "$NOT_A_REPO" origin fix-ci/lint

	assert_reason "not a git repository"
}

@test "diagnostics: missing git named as the cause" {
	run_wrapper_without_git "$NO_MARKER" origin fix-ci/lint

	assert_reason "git is not installed"
}
