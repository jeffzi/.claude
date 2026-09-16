#!/usr/bin/env bats

load helpers/hooks
load helpers/release

setup() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)
}

teardown() {
	cleanup_tmpdir_root
}

# ── Marker gate ──────────────────────────────────────────────────────────────

@test "marker gate: a start without the marker is refused naming /release" {
	local work state_before
	work=$(setup_release_pair)
	rm -f "$(release_marker_path "$work")"
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "/release"
	assert_repo_state "$work" "$state_before"
}

@test "marker gate: the missing marker is the reason even when later checks would fail too" {
	local work
	work=$(setup_release_pair)
	rm -f "$(release_marker_path "$work")"
	git -C "$work" switch -q -c feature/x
	printf 'dirty\n' >"$work/README"

	run_release "$work" start nonsense

	assert_refused
	assert_reason "/release"
}

@test "marker gate: a stale marker reads as absent" {
	local work
	work=$(setup_release_pair)
	backdate_release_marker "$work" "$STALE_OFFSET_MINUTES"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "/release"
	assert_ref_absent "$work" v1.2
}

@test "marker gate: a future-dated marker reads as absent" {
	local work
	work=$(setup_release_pair)
	backdate_release_marker "$work" "$FUTURE_OFFSET_MINUTES"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "/release"
	assert_ref_absent "$work" v1.2
}

@test "marker gate: a stat that answers neither dialect is named instead of reading as no marker" {
	local work bin
	work=$(setup_release_pair)
	bin=$(failing_stat_bin "$TMPDIR_ROOT/nostat")

	run_script_on_path "$work" "$bin:$PATH" "$RELEASE_SCRIPT" start 1.2.0

	assert_run_failed 1
	assert_reason "marker age cannot be read"
	assert_ref_absent "$work" v1.2
}

@test "marker gate: status runs without a marker" {
	local work
	work=$(setup_open_release)
	rm -f "$(release_marker_path "$work")"

	run_release "$work" status

	assert_run_ok
	assert_first_line "release: v0.1 0.1.0"
}

@test "marker gate: a merge without the marker is refused naming /release before the branch check" {
	local work
	work=$(setup_plan_repo widget)
	rm -f "$(release_marker_path "$work")"
	git -C "$work" switch -q main

	run_merge "$work"

	assert_refused
	assert_reason "/release"
	assert_stderr_excludes "is not a plan branch"
}

@test "marker gate: a finish without the marker is refused naming /release before the branch check" {
	local work
	work=$(setup_finish_repo)
	rm -f "$(release_marker_path "$work")"
	git -C "$work" switch -q main

	run_finish "$work" --check

	assert_refused
	assert_reason "/release"
	assert_stderr_excludes "not on a release branch"
}

# ── Arguments ────────────────────────────────────────────────────────────────

@test "arguments: --help prints the usage line on stdout and succeeds" {
	local work
	work=$(setup_release_pair)

	run_release "$work" --help

	assert_help_printed
}

@test "arguments: -h outside a git repo prints the usage line on stdout and succeeds" {
	local dir="$TMPDIR_ROOT/nogit"
	mkdir -p "$dir"
	export GIT_CEILING_DIRECTORIES="$TMPDIR_ROOT"

	run_release "$dir" -h

	assert_help_printed
}

@test "arguments: --help after a subcommand without the marker prints usage and changes nothing" {
	local work state_before
	work=$(setup_release_pair)
	rm -f "$(release_marker_path "$work")"
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --help

	assert_help_printed
	assert_repo_state "$work" "$state_before"
	assert_absent "$(release_marker_path "$work")"
}

@test "arguments: an unknown subcommand is refused naming it with the usage line" {
	local work
	work=$(setup_release_pair)

	run_release "$work" bogus

	assert_refused
	assert_reason "unknown subcommand 'bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: no subcommand is refused with the usage line" {
	local work
	work=$(setup_release_pair)

	run_release "$work"

	assert_refused
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option is refused naming it with the usage line" {
	local work
	work=$(setup_release_pair)

	run_release "$work" start 1.2.0 --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option after status is refused naming it with the usage line" {
	local work
	work=$(setup_open_release)

	run_release "$work" status --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: a bare argument after status is refused naming it with the usage line" {
	local work
	work=$(setup_open_release)

	run_release "$work" status extra

	assert_refused
	assert_reason "'extra'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option after merge is refused naming it with the usage line" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: an unknown option after finish is refused naming it with the usage line" {
	local work
	work=$(setup_finish_repo)

	run_release "$work" finish --check --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

# ── start ────────────────────────────────────────────────────────────────────

@test "start: cuts vX.Y from main, records the version, pushes it with upstream, and ends on it" {
	local work main_before
	work=$(setup_release_pair)
	main_before=$(git -C "$work" rev-parse main)

	run_release "$work" start 1.2.0

	assert_run_ok
	assert_rev_at "$work" v1.2 "$main_before"
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_ref_at "$(bare_of "$work")" v1.2 "$main_before"
	assert_upstream_at "$work" v1.2 origin/v1.2
	assert_on_branch "$work" v1.2
}

@test "start: a failed push keeps the branch and its key and exits 1 naming the push" {
	local work main_before
	work=$(setup_release_pair)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_release "$work" start 1.2.0

	assert_run_failed 1
	assert_reason "pushing v1.2 to origin failed"
	assert_rev_at "$work" v1.2 "$main_before"
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_ref_absent "$(bare_of "$work")" v1.2
}

@test "start: a repeat after a failed push pushes the existing branch with upstream and ends on it" {
	local work main_before
	work=$(setup_release_pair)
	git -C "$work" branch v1.2 main
	git -C "$work" config branch.v1.2.release 1.2.0
	main_before=$(git -C "$work" rev-parse main)

	run_release "$work" start 1.2.0

	assert_run_ok
	assert_stdout_line "release: v1.2 was already cut for 1.2.0 and is now pushed."
	assert_ref_at "$(bare_of "$work")" v1.2 "$main_before"
	assert_upstream_at "$work" v1.2 origin/v1.2
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_on_branch "$work" v1.2
}

@test "start: a version whose branch origin already has is refused naming it" {
	local work state_before
	work=$(setup_open_release)
	state_before=$(repo_state "$work")

	run_release "$work" start 0.1.0

	assert_refused
	assert_reason v0.1
	assert_repo_state "$work" "$state_before"
}

@test "start: off main is refused naming the branch" {
	local work state_before
	work=$(setup_release_pair)
	git -C "$work" switch -q -c feature/x
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "feature/x"
	assert_reason "main"
	assert_repo_state "$work" "$state_before"
}

@test "start: an unstaged change is refused as unstaged" {
	local work
	work=$(setup_release_pair)
	printf 'dirty\n' >"$work/README"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "unstaged changes"
	assert_ref_absent "$work" v1.2
}

@test "start: a staged change is refused as staged" {
	local work
	work=$(setup_release_pair)
	printf 'staged\n' >"$work/README"
	git -C "$work" add README

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "staged changes"
	assert_ref_absent "$work" v1.2
}

@test "start: a main behind origin/main is refused as out of sync" {
	local work
	work=$(setup_release_pair)
	advance_origin_main "$work"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "differs from origin/main"
	assert_ref_absent "$work" v1.2
}

@test "start: an unreachable origin is refused as a failed fetch" {
	local work
	work=$(setup_release_pair)
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "'git fetch origin main' failed"
	assert_ref_absent "$work" v1.2
}

@test "start: an existing branch carrying a release key is refused naming it" {
	local work state_before
	work=$(setup_open_release)
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "v0.1"
	assert_repo_state "$work" "$state_before"
}

@test "start: the same version keyed on another branch is refused naming that branch" {
	local work state_before
	work=$(setup_release_pair)
	git -C "$work" branch feature/x main
	git -C "$work" config branch.feature/x.release 1.2.0
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "feature/x"
	assert_repo_state "$work" "$state_before"
}

@test "start: an existing vX.Y branch is refused naming it" {
	local work state_before
	work=$(setup_release_pair)
	git -C "$work" branch v1.2 main
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0

	assert_refused
	assert_reason "v1.2 already exists"
	assert_repo_state "$work" "$state_before"
}

@test "start: a version that is not X.Y.Z is refused naming it" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" start v1.2

	assert_refused
	assert_reason "'v1.2'"
	assert_repo_state "$work" "$state_before"
}

@test "start: a second bare argument is refused naming it" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 1.3.0

	assert_refused
	assert_reason "'1.3.0'"
	assert_repo_state "$work" "$state_before"
}

@test "start: a missing version is refused asking for one" {
	local work
	work=$(setup_release_pair)

	run_release "$work" start

	assert_refused
	assert_reason "start needs a version"
}

# ── start --adopt ────────────────────────────────────────────────────────────

@test "adopt: records the version on the current branch without cutting or pushing" {
	local work bare_before
	work=$(setup_release_pair)
	add_branch_with_commit "$work" v1.2 main
	git -C "$work" switch -q v1.2
	bare_before=$(git -C "$(bare_of "$work")" for-each-ref --format='%(refname) %(objectname)')

	run_release "$work" start 1.2.0 --adopt

	assert_run_ok
	assert_config_at "$work" branch.v1.2.release 1.2.0
	assert_on_branch "$work" v1.2
	[[ "$(git -C "$(bare_of "$work")" for-each-ref --format='%(refname) %(objectname)')" == "$bare_before" ]]
}

@test "adopt: on main is refused" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --adopt

	assert_refused
	assert_reason "main"
	assert_repo_state "$work" "$state_before"
}

@test "adopt: a branch already carrying a release key is refused naming it" {
	local work state_before
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --adopt

	assert_refused
	assert_reason "v0.1"
	assert_repo_state "$work" "$state_before"
}

@test "adopt: a branch that does not contain main is refused" {
	local work state_before
	work=$(setup_release_pair)
	add_branch_with_commit "$work" v1.2 main
	commit_file "$work" MOVED "main moved on"
	git -C "$work" switch -q v1.2
	state_before=$(repo_state "$work")

	run_release "$work" start 1.2.0 --adopt

	assert_refused
	assert_reason "does not contain main"
	assert_repo_state "$work" "$state_before"
}

# ── status ───────────────────────────────────────────────────────────────────

@test "status: with no release open prints exactly one line" {
	local work
	work=$(setup_release_pair)

	run_release "$work" status

	assert_run_ok
	[[ "$RUN_STDOUT" == "release: none" ]] || {
		printf 'stdout is:\n%s\nexpected only "release: none"\n' "$RUN_STDOUT" >&2
		return 1
	}
}

@test "status: from a plan branch the first line names the release branch and its version" {
	local work
	work=$(setup_open_release)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" switch -q plan/widget

	run_release "$work" status

	assert_run_ok
	assert_first_line "release: v0.1 0.1.0"
}

@test "status: lists the commits the release carries beyond main" {
	local work short
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" FEATURE "feat: add the widget"
	short=$(git -C "$work" rev-parse --short v0.1)

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "$short feat: add the widget"
}

@test "status: lists only the unmerged plan branches recorded against the release" {
	local work
	work=$(setup_open_release)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" config branch.plan/widget.planBase v0.1
	git -C "$work" branch plan/landed v0.1
	git -C "$work" config branch.plan/landed.planBase v0.1
	add_branch_with_commit "$work" plan/other main
	git -C "$work" config branch.plan/other.planBase main

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "plan/widget"
	assert_stdout_excludes "plan/landed"
	assert_stdout_excludes "plan/other"
}

@test "status: an untouched release is in sync with origin and holds nothing beyond main" {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "commits beyond main: none"
	assert_stdout_includes "unmerged plan branches: none"
	assert_stdout_includes "origin/v0.1: 0 ahead, 0 behind"
	assert_stdout_includes "main: is an ancestor of v0.1"
}

@test "status: reports the release ahead of origin from the tracking ref without fetching" {
	local work
	work=$(setup_open_release)
	git -C "$work" switch -q v0.1
	commit_file "$work" FEATURE "feat: add the widget"
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "origin/v0.1: 1 ahead, 0 behind"
	assert_stderr_excludes "fatal"
}

@test "status: reports the release behind origin" {
	local work
	work=$(setup_open_release)
	advance_origin_branch "$work" v0.1
	git -C "$work" fetch -q origin

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "origin/v0.1: 0 ahead, 1 behind"
}

@test "status: reports a release branch origin does not have" {
	local work
	work=$(setup_release_pair)
	git -C "$work" branch v0.1 main
	git -C "$work" config branch.v0.1.release 0.1.0

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "origin/v0.1: absent"
}

@test "status: reports main moved past the fork point" {
	local work
	work=$(setup_open_release)
	commit_file "$work" MOVED "main moved on"

	run_release "$work" status

	assert_run_ok
	assert_stdout_includes "main: has moved past the fork point"
}
