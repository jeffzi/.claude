#!/usr/bin/env bats

load helpers/hooks

USAGE_LINE="usage: plan-branch.sh create <slug> | base [plan/<slug>]"

setup() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)
}

teardown() {
	cleanup_tmpdir_root
}

# ── Fixtures ─────────────────────────────────────────────────────────────────

# Repo on main with one commit and a plan/$1 branch recording $2 as its base,
# left on main; prints the repo dir.
setup_repo_with_plan_branch() {
	local slug="$1" base="$2" repo
	repo=$(setup_repo plan)
	git -C "$repo" branch "plan/$slug"
	git -C "$repo" config "branch.plan/$slug.planBase" "$base"
	printf '%s' "$repo"
}

# ── Invocation ───────────────────────────────────────────────────────────────

# Run plan-branch.sh from $1 with remaining args.
run_plan_branch() {
	local repo="$1"
	shift
	run_script "$repo" "$PLAN_BRANCH_SCRIPT" "$@"
}

# ── Assertions ───────────────────────────────────────────────────────────────

# Config key $2 of repo $1 holds exactly $3.
assert_config_at() {
	local repo="$1" key="$2" want="$3" got
	got=$(git -C "$repo" config --get "$key") || got="<unset>"
	[[ "$got" == "$want" ]] || {
		printf '%s is %s, expected %s\n' "$key" "$got" "$want" >&2
		return 1
	}
}

# Snapshot of the repo at $1 a run could change: HEAD, local refs, local config, work tree.
repo_state() {
	local repo="$1"
	git -C "$repo" symbolic-ref HEAD
	git -C "$repo" for-each-ref --format='%(refname) %(objectname)'
	git -C "$repo" config --list --local
	git -C "$repo" status --porcelain --untracked-files=all
}

# ── Shared constant ──────────────────────────────────────────────────────────

@test "shared constant: branch-policy.sh exposes planBase as the plan base config key" {
	local got

	got=$(bash -c '. "$1"; printf "%s" "$PLAN_BASE_CONFIG_KEY"' _ "$BRANCH_POLICY_LIB")

	[[ "$got" == planBase ]] || {
		printf 'PLAN_BASE_CONFIG_KEY is %s, expected planBase\n' "$got" >&2
		return 1
	}
}

# ── Arguments ────────────────────────────────────────────────────────────────

@test "arguments: --help prints the usage line on stdout and succeeds" {
	local repo
	repo=$(setup_repo plan)

	run_plan_branch "$repo" --help

	assert_help_printed
}

@test "arguments: -h outside a git repo prints the usage line on stdout and succeeds" {
	local dir="$TMPDIR_ROOT/nogit"
	mkdir -p "$dir"
	export GIT_CEILING_DIRECTORIES="$TMPDIR_ROOT"

	run_plan_branch "$dir" -h

	assert_help_printed
}

@test "arguments: an unknown subcommand is refused naming it with the usage line" {
	local repo state_before
	repo=$(setup_repo plan)
	state_before=$(repo_state "$repo")

	run_plan_branch "$repo" bogus

	assert_refused
	assert_reason "unknown subcommand 'bogus'"
	assert_reason "$USAGE_LINE"
	assert_repo_state "$repo" "$state_before"
}

# ── create ───────────────────────────────────────────────────────────────────

@test "create: switches to the plan branch and records the starting branch as its base" {
	local repo
	repo=$(setup_repo plan)

	run_plan_branch "$repo" create widget

	assert_run_ok
	assert_on_branch "$repo" plan/widget
	assert_config_at "$repo" branch.plan/widget.planBase main
	assert_stdout_includes "plan/widget"
	assert_stdout_includes "main"
}

@test "create: records the branch the run started on, not the trunk" {
	local repo
	repo=$(setup_repo plan)
	git -C "$repo" switch -q -c feature/x

	run_plan_branch "$repo" create widget

	assert_run_ok
	assert_on_branch "$repo" plan/widget
	assert_config_at "$repo" branch.plan/widget.planBase feature/x
}

@test "create: an untracked file does not count as a dirty tree" {
	local repo
	repo=$(setup_repo plan)
	printf 'scratch\n' >"$repo/NOTES"

	run_plan_branch "$repo" create widget

	assert_run_ok
	assert_on_branch "$repo" plan/widget
}

@test "create: an unstaged change is refused as unstaged and changes nothing" {
	local repo state_before
	repo=$(setup_repo plan)
	printf 'dirty\n' >"$repo/README"
	state_before=$(repo_state "$repo")

	run_plan_branch "$repo" create widget

	assert_refused
	assert_reason "unstaged changes"
	assert_repo_state "$repo" "$state_before"
}

@test "create: a staged change is refused as staged and changes nothing" {
	local repo state_before
	repo=$(setup_repo plan)
	printf 'staged\n' >"$repo/README"
	git -C "$repo" add README
	state_before=$(repo_state "$repo")

	run_plan_branch "$repo" create widget

	assert_refused
	assert_reason "staged changes"
	assert_repo_state "$repo" "$state_before"
}

@test "create: a run already on a plan branch is refused naming that branch and changes nothing" {
	local repo state_before
	repo=$(setup_repo plan)
	git -C "$repo" switch -q -c plan/other
	state_before=$(repo_state "$repo")

	run_plan_branch "$repo" create widget

	assert_refused
	assert_reason "plan/other"
	assert_repo_state "$repo" "$state_before"
}

@test "create: an existing plan branch is refused as already existing and changes nothing" {
	local repo state_before
	repo=$(setup_repo_with_plan_branch widget main)
	state_before=$(repo_state "$repo")

	run_plan_branch "$repo" create widget

	assert_refused
	assert_reason "plan/widget already exists"
	assert_repo_state "$repo" "$state_before"
}

@test "create: a missing slug is refused with the usage line and changes nothing" {
	local repo state_before
	repo=$(setup_repo plan)
	state_before=$(repo_state "$repo")

	run_plan_branch "$repo" create

	assert_refused
	assert_reason "$USAGE_LINE"
	assert_repo_state "$repo" "$state_before"
}

# ── base ─────────────────────────────────────────────────────────────────────

@test "base: without an argument prints the base recorded for the current plan branch" {
	local repo
	repo=$(setup_repo_with_plan_branch widget feature/x)
	git -C "$repo" switch -q plan/widget

	run_plan_branch "$repo" base

	assert_run_ok
	[[ "$RUN_STDOUT" == "feature/x" ]] || {
		printf 'stdout is %s, expected feature/x\n' "$RUN_STDOUT" >&2
		return 1
	}
}

@test "base: a named plan branch prints the base recorded for it" {
	local repo
	repo=$(setup_repo_with_plan_branch widget feature/x)

	run_plan_branch "$repo" base plan/widget

	assert_run_ok
	[[ "$RUN_STDOUT" == "feature/x" ]] || {
		printf 'stdout is %s, expected feature/x\n' "$RUN_STDOUT" >&2
		return 1
	}
}

@test "base: a branch outside the plan namespace is refused naming it" {
	local repo
	repo=$(setup_repo_with_plan_branch widget main)

	run_plan_branch "$repo" base feature/x

	assert_refused
	assert_reason "feature/x"
	assert_reason "not a plan branch"
}

@test "base: a plan branch without a recorded base is refused naming the config key" {
	local repo
	repo=$(setup_repo plan)
	git -C "$repo" branch plan/widget

	run_plan_branch "$repo" base plan/widget

	assert_refused
	assert_reason "branch.plan/widget.planBase"
}
