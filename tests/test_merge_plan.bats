#!/usr/bin/env bats

load helpers/hooks

# Message the fixtures write to $GIT_DIR/plan-squash/<slug>.msg.
PLAN_MSG="feat(widget): add the widget

Also fixes: the sprocket.
"

USAGE_LINE="usage: merge-plan.sh [plan/<slug>] [--force]"

setup() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)
}

teardown() {
	cleanup_tmpdir_root
}

# ── Fixtures ─────────────────────────────────────────────────────────────────

# Work repo whose trunk $2 (default main) is seeded to origin, with a plan/$1
# branch two commits ahead checked out, the trunk recorded as its base and a
# fresh merge-plan marker raised; prints the work dir.
setup_plan_repo() {
	local slug="$1" trunk="${2:-main}" work
	work=$(setup_pair plan "$trunk")
	seed_origin "$work" "$trunk"
	git -C "$work" switch -q -c "plan/$slug"
	commit_file "$work" WIDGET "first"
	commit_file "$work" SPROCKET "second"
	git -C "$work" config "branch.plan/$slug.planBase" "$trunk"
	raise_merge_marker "$work"
	printf '%s' "$work"
}

# Work repo whose main and feature/x are seeded to origin, with a plan/widget
# branch two commits ahead of feature/x checked out, branch.plan/widget.planBase
# recorded as feature/x and a fresh merge-plan marker raised; prints the work dir.
setup_plan_repo_based_on_feature() {
	local work
	work=$(setup_pair plan)
	git -C "$work" switch -q -c feature/x
	commit_file "$work" FEATURE "feature work"
	seed_origin "$work" main feature/x
	git -C "$work" switch -q -c plan/widget
	commit_file "$work" WIDGET "first"
	commit_file "$work" SPROCKET "second"
	git -C "$work" config branch.plan/widget.planBase feature/x
	raise_merge_marker "$work"
	printf '%s' "$work"
}

msg_path() {
	printf '%s/plan-squash/%s.msg' "$(git -C "$1" rev-parse --absolute-git-dir)" "$2"
}

write_msg() {
	local path
	path=$(msg_path "$1" "$2")
	mkdir -p "$(dirname "$path")"
	printf '%s' "$3" >"$path"
}

# Runs JSON a `gh run list` stub answers with.
gh_runs() {
	jq -nc --arg status "$1" --arg conclusion "$2" '[{status: $status, conclusion: $conclusion}]'
}

# Stub gh on PATH so `gh run list` prints the runs JSON $1, honouring --jq.
stub_gh() {
	local bin="$TMPDIR_ROOT/bin"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nruns=%q\n' "$1" >"$bin/gh"
	cat >>"$bin/gh" <<-'STUB'
		jq_expr=""
		while (($#)); do
			case "$1" in
			--jq)
				jq_expr="$2"
				shift 2
				;;
			*) shift ;;
			esac
		done
		if [[ -n "$jq_expr" ]]; then
			printf '%s' "$runs" | jq -r "$jq_expr"
		else
			printf '%s' "$runs"
		fi
	STUB
	chmod +x "$bin/gh"
}

# Stub gh on PATH so every invocation fails like a broken client.
stub_gh_failure() {
	local bin="$TMPDIR_ROOT/bin"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nprintf "gh: unauthenticated\\n" >&2\nexit 1\n' >"$bin/gh"
	chmod +x "$bin/gh"
}

# Puts a git on PATH that fails like a dead remote whenever an argument equals
# $1; every other invocation reaches the real git.
stub_git_failing_on() {
	local bin="$TMPDIR_ROOT/bin" real_git
	real_git=$(command -v git)
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nreal_git=%q\nneedle=%q\n' "$real_git" "$1" >"$bin/git"
	cat >>"$bin/git" <<-'STUB'
		for arg in "$@"; do
			if [[ "$arg" == "$needle" ]]; then
				printf 'fatal: unable to access origin: connection refused\n' >&2
				exit 128
			fi
		done
		exec "$real_git" "$@"
	STUB
	chmod +x "$bin/git"
}

# ── Invocation ───────────────────────────────────────────────────────────────

# Run merge-plan.sh from $1 with remaining args, stubs first on PATH.
run_merge() {
	local work="$1"
	shift
	run_script_on_path "$work" "$TMPDIR_ROOT/bin:$PATH" "$MERGE_PLAN_SCRIPT" "$@"
}

# Same, on a hermetic PATH holding only the tools the script needs — no gh,
# whatever the host installs.
run_merge_without_gh() {
	local work="$1" bin="$TMPDIR_ROOT/nogh" tool
	shift
	mkdir -p "$bin"
	for tool in bash git stat date rm; do
		ln -sf "$(command -v "$tool")" "$bin/$tool"
	done
	run_script_on_path "$work" "$bin" "$MERGE_PLAN_SCRIPT" "$@"
}

# ── Assertions ───────────────────────────────────────────────────────────────

# The last commit on branch $2 of repo $1 carries message $3 verbatim.
assert_commit_message() {
	local work="$1" branch="$2" want="$3" got
	got=$(git -C "$work" log -1 --format=%B "$branch")
	# Both sides lose their trailing newline to the substitution, so this is
	# content equality under git's own trailing-newline normalisation.
	[[ "$got" == "$(printf '%s' "$want")" ]] || {
		printf 'commit message on %s is:\n%s\nexpected:\n%s\n' "$branch" "$got" "$want" >&2
		return 1
	}
}

# Snapshot of the repo at $1 a run could change: HEAD, local refs, origin refs, work tree.
repo_state() {
	local work="$1"
	git -C "$work" symbolic-ref HEAD
	git -C "$work" for-each-ref --format='%(refname) %(objectname)'
	git -C "$(bare_of "$work")" for-each-ref --format='%(refname) %(objectname)'
	git -C "$work" status --porcelain --untracked-files=all
}

# ── Marker gate ──────────────────────────────────────────────────────────────

@test "marker gate: a run without the marker is refused naming /merge-plan" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	drop_merge_marker "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "/merge-plan"
	assert_rev_at "$work" main "$main_before"
}

@test "marker gate: the missing marker is the reason even when later checks would fail too" {
	local work
	work=$(setup_plan_repo widget)
	drop_merge_marker "$work"
	printf 'dirty\n' >"$work/README"

	run_merge_without_gh "$work"

	assert_refused
	assert_reason "/merge-plan"
}

@test "marker gate: a stat that answers neither dialect is named instead of reading as no marker" {
	local work bin main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	bin=$(failing_stat_bin "$TMPDIR_ROOT/nostat")
	main_before=$(git -C "$work" rev-parse main)

	run_script_on_path "$work" "$bin:$TMPDIR_ROOT/bin:$PATH" "$MERGE_PLAN_SCRIPT"

	assert_run_failed 1
	assert_reason "marker age cannot be read"
	assert_rev_at "$work" main "$main_before"
}

# ── Arguments ────────────────────────────────────────────────────────────────

@test "arguments: --help prints the usage line on stdout and succeeds" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" --help

	assert_help_printed
}

@test "arguments: -h outside a git repo prints the usage line on stdout and succeeds" {
	local dir="$TMPDIR_ROOT/nogit"
	mkdir -p "$dir"
	export GIT_CEILING_DIRECTORIES="$TMPDIR_ROOT"

	run_merge "$dir" -h

	assert_help_printed
}

@test "arguments: --help after a branch argument without the marker prints usage and changes nothing" {
	local work state_before
	work=$(setup_plan_repo widget)
	drop_merge_marker "$work"
	state_before=$(repo_state "$work")

	run_merge "$work" plan/x --help

	assert_help_printed
	assert_repo_state "$work" "$state_before"
	assert_absent "$(merge_marker_path "$work")"
}

@test "arguments: an unknown option is refused naming it with the usage line" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" --bogus

	assert_refused
	assert_reason "unknown option '--bogus'"
	assert_reason "$USAGE_LINE"
}

@test "arguments: naming two branches is refused" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" plan/widget plan/other

	assert_refused
	assert_reason "only one branch may be named"
}

# ── Branch resolution ────────────────────────────────────────────────────────

@test "branch resolution: no argument off a plan branch is refused naming the branch" {
	local work
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	git -C "$work" switch -q -c feature/other

	run_merge "$work"

	assert_refused
	assert_reason "feature/other"
}

@test "branch resolution: a detached HEAD with no argument is refused asking for the branch" {
	local work
	work=$(setup_plan_repo widget)
	git -C "$work" switch -q --detach HEAD

	run_merge "$work"

	assert_refused
	assert_reason "HEAD is detached"
}

@test "branch resolution: a named plan branch that does not exist is refused" {
	local work
	work=$(setup_plan_repo widget)

	run_merge "$work" plan/absent

	assert_refused
	assert_reason "not a local branch"
}

@test "branch resolution: an explicit plan branch is merged from main" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	git -C "$work" switch -q main
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work" plan/widget

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
	assert_on_branch "$work" main
}

# ── Recorded base branch ─────────────────────────────────────────────────────

@test "recorded base: a recorded master takes the squash and is pushed to origin/master" {
	local work bare master_before squashed
	work=$(setup_plan_repo widget master)
	bare=$(bare_of "$work")
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	master_before=$(git -C "$work" rev-parse master)

	run_merge "$work"

	assert_run_ok
	assert_rev_at "$work" master^ "$master_before"
	assert_commit_message "$work" master "$PLAN_MSG"
	squashed=$(git -C "$work" rev-parse master)
	assert_ref_at "$bare" master "$squashed"
	assert_on_branch "$work" master
}

@test "recorded base: a plan branch with no recorded base is refused naming the key and plan-branch.sh" {
	local work state_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	git -C "$work" config --unset branch.plan/widget.planBase
	state_before=$(repo_state "$work")

	run_merge "$work"

	assert_refused
	assert_reason "branch.plan/widget.planBase"
	assert_reason "plan-branch.sh"
	assert_repo_state "$work" "$state_before"
}

@test "recorded base: the squash lands on the recorded branch and leaves main untouched" {
	local work bare feature_before main_before branch_tree squashed
	work=$(setup_plan_repo_based_on_feature)
	bare=$(bare_of "$work")
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
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

@test "recorded base: a base behind its origin counterpart is refused as out of sync" {
	local work feature_before
	work=$(setup_plan_repo_based_on_feature)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	advance_origin_branch "$work" feature/x
	feature_before=$(git -C "$work" rev-parse feature/x)

	run_merge "$work"

	assert_refused
	assert_reason "differs from origin/feature/x"
	assert_rev_at "$work" feature/x "$feature_before"
	assert_ref_present "$work" plan/widget
}

@test "recorded base: a recorded branch that no longer exists locally is refused naming it" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	git -C "$work" config branch.plan/widget.planBase feature/gone
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "feature/gone"
	assert_rev_at "$work" main "$main_before"
	assert_ref_present "$work" plan/widget
}

@test "recorded base: a base holding a commit the plan branch lacks is refused until rebased" {
	local work feature_before
	work=$(setup_plan_repo_based_on_feature)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
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

# ── Clean tree precondition ──────────────────────────────────────────────────

@test "clean tree: an unstaged change is refused as unstaged" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	printf 'dirty\n' >"$work/README"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "unstaged changes"
	assert_rev_at "$work" main "$main_before"
}

@test "clean tree: a staged change is refused as staged" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	printf 'staged\n' >"$work/README"
	git -C "$work" add README
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "staged changes"
	assert_rev_at "$work" main "$main_before"
}

# ── Message file precondition ────────────────────────────────────────────────

@test "message file: a missing message file is refused naming its path" {
	local work main_before
	work=$(setup_plan_repo widget)
	stub_gh "$(gh_runs completed success)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "no squash message at $(msg_path "$work" widget)"
	assert_rev_at "$work" main "$main_before"
}

@test "message file: an empty message file is refused as empty" {
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

# ── Base-in-sync precondition ────────────────────────────────────────────────

@test "base sync: a main behind origin/main is refused as out of sync" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	advance_origin_main "$work"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "differs from origin/main"
	assert_rev_at "$work" main "$main_before"
}

@test "base sync: an unreachable origin is refused as a failed fetch" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
	git -C "$work" remote set-url origin "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_refused
	assert_reason "'git fetch origin main' failed"
	assert_rev_at "$work" main "$main_before"
}

# ── CI gate ──────────────────────────────────────────────────────────────────

@test "ci gate: a failed run is refused naming its conclusion" {
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

@test "ci gate: an unfinished run is refused naming its status" {
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

@test "ci gate: a missing gh without --force is refused naming gh" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	main_before=$(git -C "$work" rev-parse main)

	run_merge_without_gh "$work"

	assert_refused
	assert_reason "gh is not installed"
	assert_rev_at "$work" main "$main_before"
}

@test "ci gate: a failing gh client is refused as a failed run lookup" {
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

@test "ci gate: a missing run for the branch tip is refused as no run found" {
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

@test "ci gate: --force merges despite a failed run" {
	local work main_before
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed failure)"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work" --force

	assert_run_ok
	assert_rev_at "$work" main^ "$main_before"
}

# ── Squash merge ─────────────────────────────────────────────────────────────

@test "squash: a never-pushed branch lands as one commit with the branch tree and the message verbatim, and is gone" {
	local work main_before branch_tree
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	stub_gh "$(gh_runs completed success)"
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

@test "squash: origin/main is pushed, both branch copies and the message file are gone" {
	local work bare msg squashed
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	write_msg "$work" widget "$PLAN_MSG"
	msg=$(msg_path "$work" widget)
	stub_gh "$(gh_runs completed success)"
	seed_origin "$work" plan/widget

	run_merge "$work"

	assert_run_ok
	squashed=$(git -C "$work" rev-parse main)
	assert_ref_at "$bare" main "$squashed"
	assert_ref_absent "$work" plan/widget
	assert_ref_absent "$bare" plan/widget
	assert_absent "$msg"
	assert_on_branch "$work" main
}

@test "squash: a message body line starting with # survives the commit" {
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

# ── Push failure ─────────────────────────────────────────────────────────────

@test "push failure: the squash commit, the branch, and the message file are kept" {
	local work main_before msg
	work=$(setup_plan_repo widget)
	write_msg "$work" widget "$PLAN_MSG"
	msg=$(msg_path "$work" widget)
	stub_gh "$(gh_runs completed success)"
	git -C "$work" config remote.origin.pushurl "$TMPDIR_ROOT/missing.git"
	main_before=$(git -C "$work" rev-parse main)

	run_merge "$work"

	assert_run_failed 1
	assert_reason "pushing main to origin failed"
	assert_rev_at "$work" main^ "$main_before"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}

# ── Remote failure during cleanup ────────────────────────────────────────────

@test "cleanup: a failing ls-remote is reported and leaves the branches in place" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	write_msg "$work" widget "$PLAN_MSG"
	msg=$(msg_path "$work" widget)
	stub_gh "$(gh_runs completed success)"
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

@test "cleanup: a failing remote deletion is reported after the base is pushed" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	write_msg "$work" widget "$PLAN_MSG"
	msg=$(msg_path "$work" widget)
	stub_gh "$(gh_runs completed success)"
	seed_origin "$work" plan/widget
	stub_git_failing_on --delete

	run_merge "$work"

	assert_run_failed 1
	assert_reason "deleting plan/widget from origin failed"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$bare" plan/widget
	assert_present "$msg"
}

@test "cleanup: a failing local branch deletion is reported after the base is pushed" {
	local work msg bare
	work=$(setup_plan_repo widget)
	bare=$(bare_of "$work")
	write_msg "$work" widget "$PLAN_MSG"
	msg=$(msg_path "$work" widget)
	stub_gh "$(gh_runs completed success)"
	stub_git_failing_on -D

	run_merge "$work"

	assert_run_failed 1
	assert_reason "deleting the local plan/widget failed"
	assert_ref_at "$bare" main "$(git -C "$work" rev-parse main)"
	assert_ref_present "$work" plan/widget
	assert_present "$msg"
}
