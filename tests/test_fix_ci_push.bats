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
	seed_origin "$REFUSE" main

	export DELETE_FLAG
	DELETE_FLAG=$(setup_marked_pair delete_flag)
	add_branch "$DELETE_FLAG" plan/x
	seed_origin "$DELETE_FLAG" main fix-ci/lint plan/x

	export DELETE_COLON
	DELETE_COLON=$(setup_marked_pair delete_colon)
	add_branch "$DELETE_COLON" plan/x
	seed_origin "$DELETE_COLON" main fix-ci/lint plan/x

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
}

@test "pass-through: push -u of a fix-ci branch lands in origin" {
	run_wrapper "$UPSTREAM" -u origin fix-ci/lint

	assert_run_ok
	assert_ref_present "$(bare_of "$UPSTREAM")" fix-ci/lint
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

@test "delete scope: push --delete of a fix-ci and a plan branch removes both from origin" {
	run_wrapper "$DELETE_FLAG" origin --delete fix-ci/lint plan/x

	assert_run_ok
	assert_ref_absent "$(bare_of "$DELETE_FLAG")" fix-ci/lint
	assert_ref_absent "$(bare_of "$DELETE_FLAG")" plan/x
}

@test "delete scope: delete refspecs for a fix-ci and a plan branch remove both from origin" {
	run_wrapper "$DELETE_COLON" origin :fix-ci/lint :plan/x

	assert_run_ok
	assert_ref_absent "$(bare_of "$DELETE_COLON")" fix-ci/lint
	assert_ref_absent "$(bare_of "$DELETE_COLON")" plan/x
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
