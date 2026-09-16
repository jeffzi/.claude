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

# ── merge: fixup fold ────────────────────────────────────────────────────────

@test "merge: each fixup lands in its release commit and the plan work becomes one squash commit on top" {
	local work bare subjects_before tip_before plan_tree msg
	work=$(setup_fold_repo)
	bare=$(bare_of "$work")
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	seed_origin "$work" plan/x
	subjects_before=$(release_subjects "$work" v0.1)
	tip_before=$(git -C "$work" rev-parse v0.1)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_blob_at "$work" "$(commit_by_subject "$work" v0.1 "$ALPHA_SUBJECT"):alpha.txt" "fixup! $ALPHA_SUBJECT"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_commit_message "$work" v0.1 "$PLAN_MSG"
	assert_ref_at "$bare" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$work" plan/x
	assert_ref_absent "$bare" plan/x
	assert_absent "$msg"
	assert_on_branch "$work" v0.1
	assert_stdout_includes "$tip_before"
}

@test "merge: an all-fixup branch folds without a squash commit and needs no message file" {
	local work subjects_before plan_tree
	work=$(setup_release_with_commits)
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	subjects_before=$(release_subjects "$work" v0.1)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" v0.1 "$subjects_before"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_ref_absent "$work" plan/x
	assert_on_branch "$work" v0.1
}

@test "merge: ordinary commits among the fixups still land as one squash commit" {
	local work subjects_before plan_tree
	work=$(setup_release_with_commits)
	commit_file "$work" widget.txt "feat: add the widget"
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" sprocket.txt "feat: add the sprocket"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	write_msg "$work" x "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	subjects_before=$(release_subjects "$work" v0.1)
	plan_tree=$(git -C "$work" rev-parse "plan/x^{tree}")

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_rev_at "$work" "v0.1^{tree}" "$plan_tree"
	assert_commit_message "$work" v0.1 "$PLAN_MSG"
}

@test "merge: an all-fixup fold moves origin's release branch and deletes the plan branch there" {
	local work bare
	work=$(setup_release_with_commits)
	commit_file "$work" alpha.txt "fixup! $ALPHA_SUBJECT"
	commit_file "$work" beta.txt "fixup! $BETA_SUBJECT"
	stub_gh "$(gh_runs completed success)"
	seed_origin "$work" plan/x
	bare=$(bare_of "$work")

	run_merge "$work"

	assert_run_ok
	assert_ref_at "$bare" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$bare" plan/x
}

@test "merge: a conflicting fixup aborts the rebase and leaves both branches as found" {
	local work plan_before base_before
	work=$(setup_conflicting_fold_repo)
	plan_before=$(git -C "$work" rev-parse plan/x)
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "fixup! $ALPHA_SUBJECT"
	assert_reason "the rebase was aborted"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_on_branch "$work" plan/x
	assert_absent "$(git -C "$work" rev-parse --absolute-git-dir)/rebase-merge"
}

@test "merge: a conflicting fixup named from another branch ends on the branch the run started from" {
	local work plan_before base_before
	work=$(setup_conflicting_fold_repo)
	git -C "$work" switch -q v0.1
	plan_before=$(git -C "$work" rev-parse plan/x)
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work" plan/x

	assert_refused
	assert_reason "fixup! $ALPHA_SUBJECT"
	assert_reason "the rebase was aborted"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_on_branch "$work" v0.1
	assert_absent "$(git -C "$work" rev-parse --absolute-git-dir)/rebase-merge"
}

@test "merge: a fixup on a base without a release key is refused as needing a release branch" {
	local work main_before
	work=$(setup_plan_repo widget)
	commit_file "$work" README "fixup! init"
	ready_widget_merge "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "release branch"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" plan/widget
}

@test "merge: a fixup naming no release commit is refused naming the fixup" {
	local work base_before
	work=$(setup_release_with_commits)
	commit_file "$work" gamma.txt "fixup! feat: add gamma"
	stub_gh "$(gh_runs completed success)"
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "fixup! feat: add gamma"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: a fixup naming a commit older than the fork point is refused naming the fixup" {
	local work base_before
	work=$(setup_release_with_commits)
	commit_file "$work" gamma.txt "fixup! init"
	stub_gh "$(gh_runs completed success)"
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "fixup! init"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: a fixup naming two release commits is refused naming both" {
	local work base_before first second
	work=$(setup_ambiguous_fold_repo)
	base_before=$(git -C "$work" rev-parse v0.1)
	first=$(git -C "$work" rev-parse --short "v0.1^")
	second=$(git -C "$work" rev-parse --short v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "$first"
	assert_reason "$second"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: another plan branch recording the same base is refused naming it" {
	local work base_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	git -C "$work" branch plan/other v0.1
	git -C "$work" config branch.plan/other.planBase v0.1
	base_before=$(git -C "$work" rev-parse v0.1)

	run_merge "$work"

	assert_refused
	assert_reason "plan/other"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_ref_present "$work" plan/x
}

@test "merge: a lease rejected by a moved origin restores both branches and names the recovery steps" {
	local work msg base_before plan_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)
	move_origin_before_push "$work" v0.1

	run_merge "$work"

	assert_run_failed 1
	assert_reason "origin/v0.1 moved"
	assert_reason "were restored"
	assert_reason "git switch v0.1"
	assert_reason "git pull --ff-only origin v0.1"
	assert_reason "git rebase --onto v0.1 $base_before plan/x"
	assert_reason "re-run"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_tree_clean "$work"
	assert_present "$msg"
}

@test "merge: a re-run after only a fetch is refused as out of sync with origin" {
	local work
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	move_origin_before_push "$work" v0.1
	run_merge "$work" plan/x
	git -C "$work" fetch -q origin

	run_merge "$work" plan/x

	assert_refused
	assert_reason "differs from origin/v0.1"
}

@test "merge: the recovery steps printed to a run made from the release branch fold and push on a re-run" {
	local work subjects_before
	work=$(setup_recovered_fold_repo v0.1)
	subjects_before=$(release_subjects "$work" v0.1)

	run_merge "$work" plan/x

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_ref_at "$(bare_of "$work")" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$work" plan/x
}

@test "merge: the recovery steps printed to a run made from the plan branch fold and push on a re-run" {
	local work subjects_before
	work=$(setup_recovered_fold_repo plan/x)
	subjects_before=$(release_subjects "$work" v0.1)

	run_merge "$work" plan/x

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_ref_at "$(bare_of "$work")" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$work" plan/x
}

@test "merge: the recovery steps printed to a run made from a third branch fold and push on a re-run" {
	local work subjects_before
	work=$(setup_recovered_fold_repo main)
	subjects_before=$(release_subjects "$work" v0.1)

	run_merge "$work" plan/x

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_ref_at "$(bare_of "$work")" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$work" plan/x
}

@test "merge: a restore that fails after a rejected lease prints both shas and their recovery commands" {
	local work base_before plan_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)
	diverge_push_target "$work" v0.1
	stub_git_failing_on "$base_before"

	run_merge "$work"

	assert_run_failed 1
	assert_reason "git branch -f v0.1 $base_before"
	assert_reason "git branch -f plan/x $plan_before"
}

@test "merge: an unreachable remote on the fold path restores both branches and says to fetch and re-run" {
	local work msg base_before plan_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"

	run_merge "$work"

	assert_run_failed 1
	assert_reason "were restored"
	assert_reason "git fetch"
	assert_reason "re-run"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_present "$msg"
}

@test "merge: a remote that cannot be reached at all restores both branches and says to re-run once it is reachable" {
	local work msg base_before plan_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)
	unreachable_origin_before_push "$work"

	run_merge "$work"

	assert_run_failed 1
	assert_reason "were restored"
	assert_reason "re-run once the remote is reachable"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_tree_clean "$work"
	assert_present "$msg"
}

@test "merge: a failed move of the release branch restores the plan branch and says so" {
	local work msg base_before plan_before lock
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)
	lock="$(git -C "$work" rev-parse --absolute-git-dir)/refs/heads/v0.1.lock"
	mkdir -p "$(dirname "$lock")"
	: >"$lock"

	run_merge "$work"

	assert_run_failed 1
	assert_reason "moving v0.1 onto the folded commits failed"
	assert_reason "plan/x was restored"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_present "$msg"
}

@test "merge: a failed squash after the fold restores both branches and the tree" {
	local work msg base_before plan_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	msg=$(msg_path "$work" x)
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)
	fail_commits "$work"

	run_merge "$work"

	assert_run_failed 1
	assert_reason "and the tree were restored"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_tree_clean "$work"
	assert_present "$msg"
}

@test "merge: a re-run after a failed squash folds and pushes" {
	local work subjects_before
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	subjects_before=$(release_subjects "$work" v0.1)
	fail_commits "$work"
	run_merge "$work" plan/x
	allow_commits "$work"

	run_merge "$work" plan/x

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_commit_message "$work" v0.1 "$PLAN_MSG"
	assert_ref_at "$(bare_of "$work")" v0.1 "$(git -C "$work" rev-parse v0.1)"
	assert_ref_absent "$work" plan/x
}

@test "merge: a merge commit on the plan branch is refused naming it" {
	local work sha
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	git -C "$work" switch -q -c side v0.1
	commit_file "$work" side.txt "feat: add the side"
	git -C "$work" switch -q plan/x
	git -C "$work" -c commit.gpgsign=false merge -q --no-ff -m "Merge branch 'side'" side
	sha=$(git -C "$work" rev-parse --short HEAD)

	assert_merge_refuses_fold "$work" "$sha"
}

@test "merge: a squash! commit on the plan branch is refused naming it" {
	local work
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	commit_file "$work" alpha.txt "squash! $ALPHA_SUBJECT"

	assert_merge_refuses_fold "$work" "squash! $ALPHA_SUBJECT"
}

@test "merge: an amend! commit on the plan branch is refused naming it" {
	local work
	work=$(setup_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	commit_file "$work" beta.txt "amend! $BETA_SUBJECT"

	assert_merge_refuses_fold "$work" "amend! $BETA_SUBJECT"
}

@test "merge: a fold that replays a plan commit as empty keeps every release commit" {
	local work subjects_before
	work=$(setup_emptied_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	subjects_before=$(release_subjects "$work" v0.1)

	run_merge "$work"

	assert_run_ok
	assert_release_subjects "$work" "v0.1^" "$subjects_before"
	assert_blob_at "$work" "$(commit_by_subject "$work" v0.1 "$ALPHA_SUBJECT"):alpha.txt" "patched alpha"
}

@test "merge: a fold that cancels a release commit restores both branches and is refused naming the counts" {
	local work base_before plan_before
	work=$(setup_vanishing_fold_repo)
	write_msg "$work" x "$PLAN_MSG"
	base_before=$(git -C "$work" rev-parse v0.1)
	plan_before=$(git -C "$work" rev-parse plan/x)

	run_merge "$work"

	assert_refused
	assert_reason "the fold left 2 commits above the fork point, fewer than the 3 v0.1 carried"
	assert_rev_at "$work" v0.1 "$base_before"
	assert_rev_at "$work" plan/x "$plan_before"
	assert_on_branch "$work" plan/x
}

@test "merge: a conflicting fixup named from a detached HEAD leaves it detached where it was" {
	local work head_before
	work=$(setup_conflicting_fold_repo)
	git -C "$work" switch -q --detach v0.1
	head_before=$(git -C "$work" rev-parse HEAD)

	run_merge "$work" plan/x

	assert_refused
	assert_reason "the rebase was aborted"
	assert_detached_at "$work" "$head_before"
}

@test "merge: a fold with ordinary commits and no message file is refused before the rebase" {
	local work state_before
	work=$(setup_fold_repo)
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "no squash message at $(msg_path "$work" x)"
	assert_repo_state "$work" "$state_before"
}

@test "merge: a fold with ordinary commits and an empty message file is refused before the rebase" {
	local work state_before
	work=$(setup_fold_repo)
	write_msg "$work" x ""
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "is empty"
	assert_repo_state "$work" "$state_before"
}
