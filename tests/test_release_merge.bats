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

# ── merge: branch resolution ─────────────────────────────────────────────────

@test "merge: naming two branches is refused" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" plan/widget plan/other

	assert_refused
	assert_reason "only one branch may be named"
}

@test "merge: no argument off a plan branch is refused naming the branch" {
	local work
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" switch -q -c feature/other

	run_merge "$work"

	assert_refused
	assert_reason "feature/other"
}

@test "merge: a detached HEAD with no argument is refused asking for the branch" {
	local work
	work=$(setup_plan_repo widget)
	git -C "$work" switch -q --detach HEAD

	run_merge "$work"

	assert_refused
	assert_reason "HEAD is detached"
}

@test "merge: a named plan branch that does not exist is refused" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" plan/absent

	assert_refused
	assert_reason "not a local branch"
}

@test "merge: an explicit plan branch is merged from main" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" switch -q main
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work" plan/widget

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_on_branch "$work" main
}

# ── merge: recorded base ─────────────────────────────────────────────────────

@test "merge: a recorded master takes the squash and is pushed to origin/master" {
	local work bare master_before squashed
	work=$(setup_plan_repo widget master)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	master_before=$(git -C "$work" rev-parse master)

	run_merge "$work"

	assert_run_ok
	assert_rev_at "$work" master^ "$master_before"
	assert_commit_message "$work" master "$PLAN_MSG"
	squashed=$(git -C "$work" rev-parse master)
	assert_ref_at "$bare" master "$squashed"
	assert_on_branch "$work" master
}

@test "merge: a plan branch with no recorded base is refused naming the key and plan-branch.sh" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" config --unset branch.plan/widget.planBase
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "branch.plan/widget.planBase"
	assert_reason "plan-branch.sh"
	assert_repo_state "$work" "$state_before"
}

@test "merge: the squash lands on the recorded branch and leaves main untouched" {
	local work bare feature_before main_before branch_tree squashed
	work=$(setup_plan_repo_based_on_feature)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	seed_origin "$work" plan/widget
	feature_before=$(git -C "$work" rev-parse feature/x)
	main_before=$(git -C "$work" rev-parse main)
	branch_tree=$(git -C "$work" rev-parse "plan/widget^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_stdout_includes "feature/x"
	assert_rev_at "$work" "feature/x^" "$feature_before"
	assert_rev_at "$work" "feature/x^{tree}" "$branch_tree"
	assert_commit_message "$work" feature/x "$PLAN_MSG"
	assert_rev_at "$work" main "$main_before"
	squashed=$(git -C "$work" rev-parse feature/x)
	assert_ref_at "$bare" feature/x "$squashed"
	assert_ref_at "$bare" main "$main_before"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$bare" plan/widget
	assert_on_branch "$work" feature/x
}

@test "merge: a base behind its origin counterpart is refused as out of sync" {
	local work feature_before
	work=$(setup_plan_repo_based_on_feature)
	ready_widget_merge "$work"
	advance_origin_branch "$work" feature/x
	feature_before=$(git -C "$work" rev-parse feature/x)

	run_merge "$work"

	assert_refused
	assert_reason "differs from origin/feature/x"
	assert_rev_at "$work" feature/x "$feature_before"
	assert_ref_present "$work" plan/widget
}

@test "merge: a recorded branch that no longer exists locally is refused naming it" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" config branch.plan/widget.planBase feature/gone
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "feature/gone"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" plan/widget
}

@test "merge: a base holding a commit the plan branch lacks is refused until rebased" {
	local work feature_before
	work=$(setup_plan_repo_based_on_feature)
	ready_widget_merge "$work"
	git -C "$work" switch -q feature/x
	commit_file "$work" ahead.txt "feature moved ahead"
	git -C "$work" push -q origin feature/x
	git -C "$work" switch -q plan/widget
	feature_before=$(git -C "$work" rev-parse feature/x)

	run_merge "$work"

	assert_refused
	assert_reason "rebase"
	assert_rev_at "$work" feature/x "$feature_before"
	assert_ref_present "$work" plan/widget
}

# ── merge: clean tree ────────────────────────────────────────────────────────

@test "merge: an unstaged change is refused as unstaged" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	printf 'dirty\n' >"$work/README"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "unstaged changes"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a staged change is refused as staged" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	printf 'staged\n' >"$work/README"
	git -C "$work" add README
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "staged changes"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: --force skips the CI gate only and still refuses an unstaged change" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	printf 'dirty\n' >"$work/README"
	state_before=$(repo_state "$work")

	run_merge "$work" --force

	assert_refused
	assert_reason "unstaged changes"
	assert_repo_state "$work" "$state_before"
}

# ── merge: message file ──────────────────────────────────────────────────────

@test "merge: a missing message file is refused naming its path" {
	local work main_before
	work=$(setup_plan_repo widget)
	stub_gh "$(gh_runs completed success)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "no squash message at $(msg_path "$work" widget)"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: an empty message file is refused as empty" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget ""
	stub_gh "$(gh_runs completed success)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "is empty"
	assert_rev_at "$work" main "$main_before"
}

# ── merge: base sync ─────────────────────────────────────────────────────────

@test "merge: a main ahead of origin/main is refused saying to push it" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" switch -q main
	commit_file "$work" LOCAL "local work"
	commit_file "$work" LATER "more local work"
	git -C "$work" switch -q plan/widget
	git -C "$work" rebase -q main
	state_before=$(repo_state_except_tracking "$work")

	run_merge "$work"

	assert_refused
	assert_reason "main has 2 commits origin lacks"
	assert_reason "git push origin main"
	assert_reason "re-run"
	assert_repo_state_except_tracking "$work" "$state_before"
}

@test "merge: a main behind origin/main is refused saying to update it and rebase the plan branch" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	advance_origin_main "$work"
	state_before=$(repo_state_except_tracking "$work")

	run_merge "$work"

	assert_refused
	assert_reason "origin/main has 1 commit the local branch lacks"
	assert_reason "git pull --ff-only origin main"
	assert_reason "rebase plan/widget onto it"
	assert_reason "re-run"
	assert_repo_state_except_tracking "$work" "$state_before"
}

@test "merge: a main diverged from origin/main is refused naming both sides" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" switch -q main
	commit_file "$work" LOCAL "local work"
	git -C "$work" switch -q plan/widget
	git -C "$work" rebase -q main
	advance_origin_main "$work"
	state_before=$(repo_state_except_tracking "$work")

	run_merge "$work"

	assert_refused
	assert_reason "main has 1 commit origin lacks"
	assert_reason "origin/main has 1 commit the local branch lacks"
	assert_reason "Reconcile the branch with origin"
	assert_reason "re-run"
	assert_repo_state_except_tracking "$work" "$state_before"
}

@test "merge: an unreachable origin is refused as a failed fetch" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"
	state_before=$(repo_state_except_tracking "$work")

	run_merge "$work"

	assert_refused
	assert_reason "'git fetch origin main' failed"
	assert_repo_state_except_tracking "$work" "$state_before"
}

# ── merge: plan branch sync ──────────────────────────────────────────────────

@test "merge: an origin copy of the plan branch at another tip is refused as out of sync" {
	local work state_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	seed_origin "$work" plan/widget
	git -C "$work" fetch -q origin
	commit_file "$work" LATER "third"
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "plan/widget"
	assert_reason "push"
	assert_repo_state "$work" "$state_before"
}

# ── merge: CI gate ───────────────────────────────────────────────────────────

@test "merge: a failed CI run is refused naming its conclusion" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "failure"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: an unfinished CI run is refused naming its status" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs in_progress "")"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "in_progress"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a missing gh without --force is refused naming gh" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	main_before=$(git -C "$work" rev-parse main)

	run_merge_without_gh "$work"

	assert_refused
	assert_reason "gh is not installed"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a failing gh client is refused as a failed run lookup" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh_failure
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "'gh run list' failed"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: a missing CI run for the branch tip is refused as no run found" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh '[]'
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "no CI run found"
	assert_rev_at "$work" main "$main_before"
}

@test "merge: --force merges despite a failed CI run" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work" --force

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
}

# ── merge: squash ────────────────────────────────────────────────────────────

@test "merge: a never-pushed branch lands as one commit with the branch tree and the message verbatim, and is gone" {
	local work main_before branch_tree
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	main_before=$(git -C "$work" rev-parse main)
	branch_tree=$(git -C "$work" rev-parse "plan/widget^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_rev_at "$work" "main^{tree}" "$branch_tree"
	assert_commit_message "$work" main "$PLAN_MSG"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$(bare_of "$work")" plan/widget
	assert_stderr_excludes "fatal"
	assert_stderr_excludes "ls-remote"
}

@test "merge: a branch equal to its fetched origin copy lands, and origin/main, both branch copies, and the message file follow" {
	local work bare msg squashed
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	seed_origin "$work" plan/widget
	git -C "$work" fetch -q origin

	run_merge "$work"

	assert_run_ok
	squashed=$(git -C "$work" rev-parse main)
	assert_ref_at "$bare" main "$squashed"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$bare" plan/widget
	assert_absent "$msg"
	assert_on_branch "$work" main
}

@test "merge: a message body line starting with # survives the commit" {
	local work msg
	msg="fix(widget): drop the sprocket

#12 was the tracking issue.
"
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$msg"
	stub_gh "$(gh_runs completed success)"

	run_merge "$work"

	assert_run_ok
	assert_commit_message "$work" main "$msg"
}

# ── merge: push and cleanup failures ─────────────────────────────────────────

@test "merge: a failed push restores the base and keeps the branch and the message file" {
	local work main_before msg
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_run_failed 1
	assert_reason "pushing main to origin failed"
	assert_reason "main was restored"
	assert_reason "re-run"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

@test "merge: a re-run after a failed push squashes and pushes" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	main_before=$(git -C "$work" rev-parse main)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"
	run_merge "$work" plan/widget
	git -C "$work" config --unset remote.origin.pushurl

	run_merge "$work" plan/widget

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_ref_at "$(bare_of "$work")" main "$(git -C "$work" rev-parse main)"
	assert_ref_absent "$work" plan/widget
}

@test "merge: a failed squash leaves the base clean and keeps the branch and the message file" {
	local work main_before msg
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	main_before=$(git -C "$work" rev-parse main)
	fail_commits "$work"

	run_merge "$work"

	assert_run_failed 1
	assert_reason "nothing here changed"
	assert_rev_at "$work" main "$main_before"
	assert_tree_clean "$work"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

@test "merge: a re-run after a failed squash squashes and pushes" {
	local work main_before
	work=$(setup_plan_repo widget)
	ready_widget_merge "$work"
	main_before=$(git -C "$work" rev-parse main)
	fail_commits "$work"
	run_merge "$work" plan/widget
	allow_commits "$work"

	run_merge "$work" plan/widget

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_ref_at "$(bare_of "$work")" main "$(git -C "$work" rev-parse main)"
	assert_ref_absent "$work" plan/widget
}

@test "merge: a failing ls-remote is reported and leaves the branches in place" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	seed_origin "$work" plan/widget
	stub_git_failing_on ls-remote

	run_merge "$work"

	assert_run_failed 1
	assert_reason "ls-remote"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$bare" plan/widget
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

@test "merge: a failing remote deletion is reported after the base is pushed" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	seed_origin "$work" plan/widget
	stub_git_failing_on --delete

	run_merge "$work"

	assert_run_failed 1
	assert_reason "deleting plan/widget from origin failed"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$bare" plan/widget
	assert_present "$msg"
}

@test "merge: a failing local branch deletion is reported after the base is pushed" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	ready_widget_merge "$work"
	msg=$(msg_path "$work" widget)
	stub_git_failing_on -D

	run_merge "$work"

	assert_run_failed 1
	assert_reason "deleting the local plan/widget failed"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}
