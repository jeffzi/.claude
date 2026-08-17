#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export NO_MARKER
	NO_MARKER=$(setup_pair no_marker)

	export STALE
	STALE=$(setup_pair stale)
	raise_marker "$STALE"
	backdate_marker "$STALE" "$STALE_OFFSET_MINUTES"

	export FUTURE
	FUTURE=$(setup_pair future)
	raise_marker "$FUTURE"
	backdate_marker "$FUTURE" "$FUTURE_OFFSET_MINUTES"

	export PLAIN
	PLAIN=$(setup_pair plain)
	raise_marker "$PLAIN"

	export UPSTREAM
	UPSTREAM=$(setup_pair upstream)
	raise_marker "$UPSTREAM"

	export REFUSE
	REFUSE=$(setup_pair refuse)
	raise_marker "$REFUSE"
	seed_origin "$REFUSE" main

	export DELETE_FLAG
	DELETE_FLAG=$(setup_pair delete_flag)
	raise_marker "$DELETE_FLAG"
	seed_origin "$DELETE_FLAG" main fix-ci/lint

	export DELETE_COLON
	DELETE_COLON=$(setup_pair delete_colon)
	raise_marker "$DELETE_COLON"
	seed_origin "$DELETE_COLON" main fix-ci/lint

	# Origin whose main has moved on independently, plus a repo-local push refspec
	# that would force-update every branch.
	export FORCE_CONFIG
	FORCE_CONFIG=$(setup_pair force_config)
	raise_marker "$FORCE_CONFIG"
	seed_origin "$FORCE_CONFIG" main
	export FORCE_CONFIG_BARE
	FORCE_CONFIG_BARE=$(bare_of "$FORCE_CONFIG")
	local other="$TMPDIR_ROOT/force_config/other"
	git clone -q "$FORCE_CONFIG_BARE" "$other"
	git -C "$other" config user.email "other@test.com"
	git -C "$other" config user.name "Other"
	touch "$other/THEIRS"
	git -C "$other" add THEIRS
	git -C "$other" -c commit.gpgsign=false commit -q -m "theirs"
	git -C "$other" push -q origin main
	export FORCE_CONFIG_HEAD
	FORCE_CONFIG_HEAD=$(git -C "$FORCE_CONFIG_BARE" rev-parse refs/heads/main)
	touch "$FORCE_CONFIG/MINE"
	git -C "$FORCE_CONFIG" add MINE
	git -C "$FORCE_CONFIG" -c commit.gpgsign=false commit -q -m "mine"
	git -C "$FORCE_CONFIG" config remote.origin.push '+refs/heads/*:refs/heads/*'

	export NOT_A_REPO
	NOT_A_REPO="$TMPDIR_ROOT/not_a_repo"
	mkdir -p "$NOT_A_REPO"
}

teardown_file() {
	[[ -n "$TMPDIR_ROOT" ]] && rm -rf "$TMPDIR_ROOT"
}

# ── Marker gate ──────────────────────────────────────────────────────────────

@test "marker gate: push without a marker is refused" {
	run_wrapper "$NO_MARKER" origin fix-ci/lint
	assert_refused
	assert_ref_absent "$(bare_of "$NO_MARKER")" fix-ci/lint
}

@test "marker gate: push under a stale marker is refused" {
	run_wrapper "$STALE" origin fix-ci/lint
	assert_refused
	assert_ref_absent "$(bare_of "$STALE")" fix-ci/lint
}

@test "marker gate: push under a future-dated marker is refused" {
	run_wrapper "$FUTURE" origin fix-ci/lint
	assert_refused
	assert_ref_absent "$(bare_of "$FUTURE")" fix-ci/lint
}

# ── Pass-through under a fresh marker ────────────────────────────────────────

@test "pass-through: push of a fix-ci branch succeeds and lands in origin" {
	run_wrapper "$PLAIN" origin fix-ci/lint
	assert_pushed
	assert_ref_present "$(bare_of "$PLAIN")" fix-ci/lint
}

@test "pass-through: push -u of a fix-ci branch succeeds and lands in origin" {
	run_wrapper "$UPSTREAM" -u origin fix-ci/lint
	assert_pushed
	assert_ref_present "$(bare_of "$UPSTREAM")" fix-ci/lint
}

# ── Flag whitelist (every force form) ────────────────────────────────────────

@test "force flag: push -f is refused" {
	run_wrapper "$REFUSE" -f origin fix-ci/lint
	assert_refused
	assert_ref_absent "$(bare_of "$REFUSE")" fix-ci/lint
}

@test "force flag: push --force-with-lease is refused" {
	run_wrapper "$REFUSE" --force-with-lease origin fix-ci/lint
	assert_refused
}

@test "force flag: push -fu (bundled force) is refused" {
	run_wrapper "$REFUSE" -fu origin fix-ci/lint
	assert_refused
}

@test "force flag: push --mirror is refused" {
	run_wrapper "$REFUSE" --mirror origin
	assert_refused
}

@test "force flag: push +main:main (force refspec) is refused" {
	run_wrapper "$REFUSE" origin +main:main
	assert_refused
}

# ── Delete scoping ───────────────────────────────────────────────────────────

@test "delete scope: push --delete main is refused" {
	run_wrapper "$REFUSE" origin --delete main
	assert_refused
}

@test "delete scope: push :main (delete refspec) is refused" {
	run_wrapper "$REFUSE" origin :main
	assert_refused
	assert_ref_present "$(bare_of "$REFUSE")" main
}

@test "delete scope: push --delete fix-ci/lint succeeds" {
	run_wrapper "$DELETE_FLAG" origin --delete fix-ci/lint
	assert_pushed
	assert_ref_absent "$(bare_of "$DELETE_FLAG")" fix-ci/lint
}

@test "delete scope: push :fix-ci/lint (delete refspec) succeeds" {
	run_wrapper "$DELETE_COLON" origin :fix-ci/lint
	assert_pushed
	assert_ref_absent "$(bare_of "$DELETE_COLON")" fix-ci/lint
}

# ── Repo config cannot inject a force ────────────────────────────────────────

@test "force config: push under a force-everything push refspec fails" {
	run_wrapper "$FORCE_CONFIG" origin
	assert_failed
	assert_ref_at "$FORCE_CONFIG_BARE" main "$FORCE_CONFIG_HEAD"
}

# ── Diagnostics ──────────────────────────────────────────────────────────────

@test "diagnostics: git's own reason for an unusable repo" {
	run_wrapper "$NOT_A_REPO" origin fix-ci/lint
	assert_reason "not a git repository"
}

@test "diagnostics: missing git named as the cause" {
	run_wrapper_without_git origin fix-ci/lint
	assert_reason "git is not installed"
}
