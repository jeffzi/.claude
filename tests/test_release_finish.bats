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

# ── finish: mode flags ───────────────────────────────────────────────────────

@test "finish: no mode flag is refused with the usage line" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" finish

	assert_refused
	assert_reason "$USAGE_LINE"
	assert_repo_state "$work" "$state_before"
}

@test "finish: two mode flags are refused with the usage line" {
	local work state_before
	work=$(setup_release_pair)
	state_before=$(repo_state "$work")

	run_release "$work" finish --check --publish

	assert_refused
	assert_reason "$USAGE_LINE"
	assert_repo_state "$work" "$state_before"
}

@test "finish: --force outside --publish is refused naming the flag" {
	local work state_before
	work=$(setup_finish_repo)
	state_before=$(repo_state "$work")

	run_release "$work" finish --check --force

	assert_refused
	assert_reason "--force"
	assert_repo_state "$work" "$state_before"
}

@test "finish: --gh-release outside --publish is refused naming the flag" {
	local work state_before
	work=$(setup_finish_repo)
	state_before=$(repo_state "$work")

	run_release "$work" finish --push --gh-release

	assert_refused
	assert_reason "--gh-release"
	assert_repo_state "$work" "$state_before"
}

# ── finish --check ───────────────────────────────────────────────────────────

@test "finish --check: off a release branch is refused" {
	local work state_before
	work=$(setup_finish_repo)
	git -C "$work" switch -q main
	state_before=$(repo_state "$work")

	run_finish "$work" --check

	assert_refused
	assert_reason "not on a release branch"
	assert_repo_state "$work" "$state_before"
}

@test "finish --check: an unstaged change is refused as unstaged" {
	local work
	work=$(setup_finish_repo)
	printf 'dirty\n' >"$work/README"

	run_finish "$work" --check

	assert_refused
	assert_reason "unstaged changes"
}

@test "finish --check: a staged change is refused as staged" {
	local work
	work=$(setup_finish_repo)
	printf 'staged\n' >"$work/README"
	git -C "$work" add README

	run_finish "$work" --check

	assert_refused
	assert_reason "staged changes"
}

@test "finish --check: a plan branch recording the release is refused naming it" {
	local work
	work=$(setup_finish_repo)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" config branch.plan/widget.planBase v0.1

	run_finish "$work" --check

	assert_refused
	assert_reason "plan/widget"
}

@test "finish --check: a release ahead of its origin counterpart is refused as out of sync" {
	local work
	work=$(setup_finish_repo)
	commit_file "$work" gamma.txt "feat: add gamma"

	run_finish "$work" --check

	assert_refused
	assert_reason "differs from origin/v0.1"
}

@test "finish --check: an unreachable origin is refused as a failed fetch" {
	local work
	work=$(setup_finish_repo)
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"

	run_finish "$work" --check

	assert_refused
	assert_reason "git fetch origin"
	assert_reason "failed"
}

@test "finish --check: a main behind origin/main is refused as out of sync" {
	local work
	work=$(setup_finish_repo)
	advance_origin_main "$work"

	run_finish "$work" --check

	assert_refused
	assert_reason "differs from origin/main"
}

@test "finish --check: a main that has moved past the release is refused saying to rebase" {
	local work
	work=$(setup_finish_repo)
	git -C "$work" switch -q main
	commit_file "$work" MOVED "main moved on"
	git -C "$work" push -q origin main
	git -C "$work" switch -q v0.1

	run_finish "$work" --check

	assert_refused
	assert_reason "rebase"
}

@test "finish --check: a ready release prints the version as a line a skill can parse" {
	local work
	work=$(setup_finish_repo)

	run_finish "$work" --check

	assert_run_ok
	assert_stdout_line "version: 0.1.0"
}

# ── finish --push ────────────────────────────────────────────────────────────

@test "finish --push: a tip without the version tag is refused naming the tag it wants" {
	local work bare tip
	work=$(setup_finish_repo)
	bare=$(bare_of "$work")
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --push

	assert_refused
	assert_reason "tag"
	assert_reason "v0.1.0"
	assert_ref_at "$bare" v0.1 "$tip"
}

@test "finish --push: a tip that is not the release commit is refused naming the subject found" {
	local work
	work=$(setup_finish_repo)
	git -C "$work" tag -a v0.1.0 -m v0.1.0

	run_finish "$work" --push

	assert_refused
	assert_reason "$ALPHA_SUBJECT"
}

@test "finish --push: pushes the tagged release commit and prints its sha as a line a skill can parse" {
	local work tip
	work=$(setup_tagged_release)
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --push

	assert_run_ok
	assert_ref_at "$(bare_of "$work")" v0.1 "$tip"
	assert_stdout_line "commit: $tip"
	assert_on_branch "$work" v0.1
}

@test "finish --push: a rejected push changes nothing and exits 1 naming the push" {
	local work bare tip origin_before
	work=$(setup_tagged_release)
	bare=$(bare_of "$work")
	advance_origin_branch "$work" v0.1
	tip=$(git -C "$work" rev-parse v0.1)
	origin_before=$(git -C "$bare" rev-parse v0.1)

	run_finish "$work" --push

	assert_run_failed 1
	assert_reason "pushing v0.1 to origin failed"
	assert_rev_at "$work" v0.1 "$tip"
	assert_ref_at "$bare" v0.1 "$origin_before"
}

# ── finish --publish ─────────────────────────────────────────────────────────

@test "finish --publish: an unstaged change is refused as unstaged" {
	local work state_before
	work=$(setup_publish_repo)
	printf 'dirty\n' >"$work/README"
	state_before=$(repo_state "$work")

	run_finish "$work" --publish

	assert_refused
	assert_reason "unstaged changes"
	assert_repo_state "$work" "$state_before"
}

@test "finish --publish: a staged change is refused as staged" {
	local work state_before
	work=$(setup_publish_repo)
	printf 'staged\n' >"$work/README"
	git -C "$work" add README
	state_before=$(repo_state "$work")

	run_finish "$work" --publish

	assert_refused
	assert_reason "staged changes"
	assert_repo_state "$work" "$state_before"
}

@test "finish --publish: a plan branch recording the release is refused naming it" {
	local work state_before
	work=$(setup_publish_repo)
	add_branch_with_commit "$work" plan/widget v0.1
	git -C "$work" config branch.plan/widget.planBase v0.1
	state_before=$(repo_state "$work")

	run_finish "$work" --publish

	assert_refused
	assert_reason "plan/widget"
	assert_repo_state "$work" "$state_before"
}

@test "finish --publish: a failed CI run is refused naming its conclusion" {
	local work main_before
	work=$(setup_publish_repo)
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "failure"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
	assert_config_at "$work" branch.v0.1.release 0.1.0
}

@test "finish --publish: --force publishes despite a failed CI run" {
	local work tip
	work=$(setup_publish_repo)
	stub_gh "$(gh_runs completed failure)"
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --publish --force

	assert_run_ok
	assert_rev_at "$work" main "$tip"
	assert_on_branch "$work" main
}

@test "finish --publish: a main behind origin/main is refused as out of sync" {
	local work main_before
	work=$(setup_publish_repo)
	advance_origin_main "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "differs from origin/main"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a main that has moved past the release is refused as not an ancestor" {
	local work main_before
	work=$(setup_publish_repo)
	git -C "$work" switch -q main
	commit_file "$work" MOVED "main moved on"
	git -C "$work" push -q origin main
	git -C "$work" switch -q v0.1
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "ancestor"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a tag that does not point at the tip is refused naming it" {
	local work main_before
	work=$(setup_publish_repo)
	git -C "$work" tag -d v0.1.0
	git -C "$work" tag v0.1.0 "v0.1^"
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "v0.1.0"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a repo without the version tag is refused naming the missing tag" {
	local work main_before
	work=$(setup_publish_repo)
	git -C "$work" tag -d v0.1.0
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "no v0.1.0 tag"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: a release ahead of its origin counterpart is refused as out of sync" {
	local work main_before
	work=$(setup_publish_repo)
	advance_origin_branch "$work" v0.1
	main_before=$(git -C "$work" rev-parse main)

	run_finish "$work" --publish

	assert_refused
	assert_reason "differs from origin/v0.1"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
}

@test "finish --publish: fast-forwards main, pushes it with the tag, drops the branch and its key, and ends on main" {
	local work bare tip
	work=$(setup_publish_repo)
	bare=$(bare_of "$work")
	tip=$(git -C "$work" rev-parse v0.1)

	run_finish "$work" --publish

	assert_run_ok
	assert_rev_at "$work" main "$tip"
	assert_ref_at "$bare" main "$tip"
	assert_tag_at "$bare" v0.1.0 "$tip"
	assert_ref_absent "$work" v0.1
	assert_ref_absent "$bare" v0.1
	assert_config_at "$work" branch.v0.1.release "<unset>"
	assert_on_branch "$work" main
}

@test "finish --publish: a failed fast-forward of main names main, the branch and the tag as kept" {
	local work main_before tip
	work=$(setup_publish_repo)
	tip=$(git -C "$work" rev-parse v0.1)
	main_before=$(git -C "$work" rev-parse main)
	stub_git_failing_on --ff-only

	run_finish "$work" --publish

	assert_run_failed 1
	assert_reason "fast-forwarding main onto v0.1 failed"
	assert_reason "main is checked out and unchanged"
	assert_reason "v0.1 and its tag are kept"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" v0.1
	assert_tag_at "$work" v0.1.0 "$tip"
}

@test "finish --publish --gh-release: creates the release from the changelog section once the tag is on origin" {
	local work notes
	work=$(setup_publish_repo)

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_gh_log_includes "release create v0.1.0 --title v0.1.0 --notes-file"
	assert_gh_log_includes "origin-tags: v0.1.0"
	notes=$(gh_notes)
	[[ "$notes" == *"- The widget."* && "$notes" != *"- The sprocket."* ]] || {
		printf 'release body is:\n%s\nexpected only the [0.1.0] section\n' "$notes" >&2
		return 1
	}
}

@test "finish --publish --gh-release: an existing release is reported, not recreated" {
	local work
	work=$(setup_publish_repo)
	stub_gh "$(gh_runs completed success)" present

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_stdout_includes "already exists"
	assert_gh_log_excludes "release create"
	assert_ref_absent "$work" v0.1
}

@test "finish --publish --gh-release: a changelog without the release section warns and creates an empty body" {
	local work
	work=$(setup_publish_repo "$CHANGELOG_WITHOUT_SECTION")

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_stderr_includes "CHANGELOG.md"
	assert_gh_log_includes "release create v0.1.0"
	assert_blob_at "$work" main:CHANGELOG.md "${CHANGELOG_WITHOUT_SECTION%$'\n'}"
	[[ -z "$(gh_notes)" ]] || {
		printf 'release body is:\n%s\nexpected an empty body\n' "$(gh_notes)" >&2
		return 1
	}
}

@test "finish --publish --gh-release: a repo without a changelog warns and creates an empty body" {
	local work
	work=$(setup_publish_repo "")

	run_finish "$work" --publish --gh-release

	assert_run_ok
	assert_stderr_includes "CHANGELOG.md"
	assert_gh_log_includes "release create v0.1.0"
	[[ -z "$(gh_notes)" ]] || {
		printf 'release body is:\n%s\nexpected an empty body\n' "$(gh_notes)" >&2
		return 1
	}
}

@test "finish --publish --gh-release: a failed push keeps main local, skips the release, and exits 1 naming the step" {
	local work bare tip main_before
	work=$(setup_publish_repo)
	bare=$(bare_of "$work")
	tip=$(git -C "$work" rev-parse v0.1)
	main_before=$(git -C "$bare" rev-parse main)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"

	run_finish "$work" --publish --gh-release

	assert_run_failed 1
	assert_reason "pushing main"
	assert_reason "locally"
	assert_rev_at "$work" main "$tip"
	assert_ref_at "$bare" main "$main_before"
	assert_ref_present "$work" v0.1
	assert_gh_log_excludes "release create"
}
