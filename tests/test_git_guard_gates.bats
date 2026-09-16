#!/usr/bin/env bats

load helpers/hooks
load helpers/guard

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export PLAN_REPO
	PLAN_REPO=$(setup_repo plan_repo)
	mkdir -p "$PLAN_REPO/.claude/plans"
	printf 'plan content\n' >"$PLAN_REPO/.claude/plans/phase.md"
	git -C "$PLAN_REPO" add -f .claude/plans/phase.md

	export UNSTAGED_PLAN_REPO
	UNSTAGED_PLAN_REPO=$(setup_repo unstaged_plan_repo)
	mkdir -p "$UNSTAGED_PLAN_REPO/.claude/plans"
	printf 'plan content\n' >"$UNSTAGED_PLAN_REPO/.claude/plans/phase.md"

	export MODIFIED_PLAN_REPO
	MODIFIED_PLAN_REPO=$(setup_repo modified_plan_repo)
	mkdir -p "$MODIFIED_PLAN_REPO/.claude/plans"
	printf 'plan content\n' >"$MODIFIED_PLAN_REPO/.claude/plans/phase.md"
	git -C "$MODIFIED_PLAN_REPO" add -f .claude/plans/phase.md
	git -C "$MODIFIED_PLAN_REPO" -c commit.gpgsign=false commit -q -m "track plan"
	printf 'edited\n' >>"$MODIFIED_PLAN_REPO/.claude/plans/phase.md"

	export DIRTY_REPO
	DIRTY_REPO=$(setup_repo dirty_repo)
	printf 'uncommitted\n' >>"$DIRTY_REPO/README"

	export TDD_ACTIVE_REPO
	TDD_ACTIVE_REPO=$(setup_repo tdd_active_repo)
	touch "$(git -C "$TDD_ACTIVE_REPO" rev-parse --absolute-git-dir)/tdd-cycle-active"

	export WT_REPO
	WT_REPO=$(setup_repo wt_repo)

	export DIRTY_WT
	DIRTY_WT=$(add_worktree "$WT_REPO" dirty)
	printf 'uncommitted\n' >>"$DIRTY_WT/README"

	export FIXCI_REPO
	FIXCI_REPO=$(setup_fix_ci_repo fixci_repo feature/ci)

	export FIXCI_STALE_REPO
	FIXCI_STALE_REPO=$(setup_fix_ci_repo fixci_stale_repo feature/ci)
	export FIXCI_STALE_MARKER
	FIXCI_STALE_MARKER=$(marker_path "$FIXCI_STALE_REPO")
	backdate_marker "$FIXCI_STALE_REPO" "$STALE_OFFSET_MINUTES"

	export PROTECTED_MAIN_REPO
	PROTECTED_MAIN_REPO=$(setup_protected_repo protected_main_repo main)

	export PROTECTED_MASTER_REPO
	PROTECTED_MASTER_REPO=$(setup_protected_repo protected_master_repo master)

	export PROTECTED_PLAN_REPO
	PROTECTED_PLAN_REPO=$(setup_protected_repo protected_plan_repo plan/x)

	export UNPROTECTED_MAIN_REPO
	UNPROTECTED_MAIN_REPO=$(setup_repo unprotected_main_repo)

	export PROTECT_FALSE_REPO
	PROTECT_FALSE_REPO=$(setup_repo protect_false_repo)
	git -C "$PROTECT_FALSE_REPO" config claude.protectMain false

	export NO_REPO_DIR="$TMPDIR_ROOT/no_repo"
	mkdir -p "$NO_REPO_DIR"

	export ABSENT_REPO="$TMPDIR_ROOT/absent_repo"

	export GLOB_DIR="$TMPDIR_ROOT/glob"
	setup_tdd_active_repo glob/repo1 >/dev/null

	export ALIGNED_REPO
	ALIGNED_REPO=$(setup_fix_ci_repo aligned feature/ci)
	add_branch "$(setup_fix_ci_repo aligned/branch feature/ci)" fix-ci/x
	add_branch "$(setup_fix_ci_repo aligned/push feature/ci)" fix-ci/x
	add_untracked_plan "$(setup_repo aligned/add)"
	setup_repo aligned/remove >/dev/null
	setup_repo aligned/worktree >/dev/null

	export WT_GLOB_REPO
	WT_GLOB_REPO=$(setup_repo wt_glob_repo)
	git -C "$WT_GLOB_REPO" worktree add -q -b wt-glob "$WT_GLOB_REPO/wt1"
	printf 'uncommitted\n' >>"$WT_GLOB_REPO/wt1/README"
}

teardown_file() {
	cleanup_tmpdir_root
}

# ── Commit ───────────────────────────────────────────────────────────────────

@test "commit: commit and commit --amend are allowed" {
	each_allowed_in "$REPO" \
		"git commit --amend" \
		"git commit -m 'msg'"
}

@test "commit: git commit with plan files staged is blocked" {
	run_guard "$PLAN_REPO" "git commit -m 'msg'"

	assert_blocked
}

# ── TDD cycle marker ─────────────────────────────────────────────────────────

@test "tdd cycle: staging and committing are blocked while a tdd-cycle marker is up" {
	each_blocked_in "$TDD_ACTIVE_REPO" \
		"git add README" \
		"git commit -m 'msg'"
}

# ── fix-ci marker (append-only push relaxed) ─────────────────────────────────

@test "fix-ci: push under marker is allowed" {
	run_guard "$FIXCI_REPO" "git push"

	assert_allowed
}

@test "fix-ci: push --delete of fix-ci branch under marker is allowed" {
	run_guard "$FIXCI_REPO" "git push origin --delete fix-ci/lint"

	assert_allowed
}

@test "fix-ci: push :fix-ci branch (delete refspec) under marker is allowed" {
	run_guard "$FIXCI_REPO" "git push origin :fix-ci/lint"

	assert_allowed
}

@test "fix-ci: push branch whose name contains -f under marker is allowed" {
	run_guard "$FIXCI_REPO" "git push origin feature/fix-flaky"

	assert_allowed
}

@test "fix-ci: deleting outside the namespaces under marker is blocked naming them" {
	local cmd
	for cmd in "git push origin --delete main" "git push origin :main" "git push --mirror"; do
		run_guard "$FIXCI_REPO" "$cmd"

		if ! assert_blocked || ! assert_guard_output_includes "fix-ci/* and plan/*"; then
			printf 'command: %s\n' "$cmd" >&2
			return 1
		fi
	done
}

@test "fix-ci: long force flags under marker are blocked as a history rewrite" {
	local cmd
	for cmd in "git push --force" "git push --force-with-lease"; do
		run_guard "$FIXCI_REPO" "$cmd"

		if ! assert_blocked || ! assert_guard_output_includes "never rewrites history"; then
			printf 'command: %s\n' "$cmd" >&2
			return 1
		fi
	done
}

@test "fix-ci: short force clusters under marker are blocked as a history rewrite" {
	local cmd
	for cmd in "git push -f" "git push -fu origin HEAD" "git push -uf origin HEAD"; do
		run_guard "$FIXCI_REPO" "$cmd"

		if ! assert_blocked || ! assert_guard_output_includes "never rewrites history"; then
			printf 'command: %s\n' "$cmd" >&2
			return 1
		fi
	done
}

@test "fix-ci: push +refspec (force) under marker is blocked as a history rewrite" {
	run_guard "$FIXCI_REPO" "git push origin +main:main"

	assert_blocked
	assert_guard_output_includes "never rewrites history"
}

@test "fix-ci: amend under marker is allowed" {
	run_guard "$FIXCI_REPO" "git commit --amend"

	assert_allowed
}

@test "fix-ci: branch -D fix-ci/* under marker is allowed" {
	run_guard "$FIXCI_REPO" "git branch -D fix-ci/lint"

	assert_allowed
}

@test "fix-ci: branch -D naming a branch outside the namespaces under marker is blocked" {
	each_blocked_in "$FIXCI_REPO" \
		"git branch -D feature" \
		"git branch -D fix-ci/lint feature" \
		"git branch -D plan/x feature/y"
}

@test "fix-ci: branch -D with no names under marker is blocked" {
	run_guard "$FIXCI_REPO" "git branch -D"

	assert_blocked
}

@test "fix-ci: --no-verify under marker is still blocked" {
	each_blocked_in "$FIXCI_REPO" \
		"git commit --no-verify -m 'msg'" \
		"git push --no-verify"
}

# ── fix-ci marker (plan/* namespace) ─────────────────────────────────────────

@test "plan namespace: the delete flag is honoured before the remote and as -d" {
	each_allowed_in "$FIXCI_REPO" \
		"git push --delete origin plan/x" \
		"git push -d origin plan/x"
}

@test "plan namespace: push --delete of a feature branch under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push origin --delete feature/y"

	assert_blocked
}

@test "plan namespace: branch -D plan/* under marker is allowed" {
	run_guard "$FIXCI_REPO" "git branch -D plan/x"

	assert_allowed
}

# ── Protected main (claude.protectMain) ──────────────────────────────────────

@test "protect main: every commit-creating subcommand on main is blocked naming the protection and /release" {
	local cmd
	for cmd in \
		"git commit -m 'msg'" \
		"git merge plan/x" \
		"git cherry-pick abc1234" \
		"git revert abc1234" \
		"git am patch.mbox" \
		"git rebase origin/main" \
		"git pull"; do
		run_guard "$PROTECTED_MAIN_REPO" "$cmd"

		if ! assert_blocked || ! assert_guard_output_includes "protected" || ! assert_guard_output_includes "/release"; then
			printf 'command: %s\n' "$cmd" >&2
			return 1
		fi
	done
}

@test "protect main: commit on master is blocked" {
	run_guard "$PROTECTED_MASTER_REPO" "git commit -m 'msg'"

	assert_blocked
}

@test "protect main: fast-forward pulls and read-only commands on main are allowed" {
	each_allowed_in "$PROTECTED_MAIN_REPO" \
		"git pull --ff-only" \
		"git fetch origin" \
		"git switch -c plan/x" \
		"git log --oneline -10"
}

@test "protect main: every guarded subcommand is allowed on a plan branch" {
	each_allowed_in "$PROTECTED_PLAN_REPO" \
		"git commit -m 'msg'" \
		"git merge main" \
		"git cherry-pick abc1234" \
		"git revert abc1234" \
		"git am patch.mbox" \
		"git rebase origin/main" \
		"git pull"
}

@test "protect main: commit on main is allowed when the key is unset or false" {
	local dir
	for dir in "$UNPROTECTED_MAIN_REPO" "$PROTECT_FALSE_REPO"; do
		run_guard "$dir" "git commit -m 'msg'"

		assert_allowed || {
			printf 'repo: %s\n' "$dir" >&2
			return 1
		}
	done
}

@test "protect main scope: commit -C at a protected repo from an unprotected cwd is blocked" {
	run_guard "$UNPROTECTED_MAIN_REPO" "git -C $PROTECTED_MAIN_REPO commit -m 'msg'"

	assert_blocked
}

@test "protect main scope: commit -C at an unprotected repo from a protected cwd is allowed" {
	run_guard "$PROTECTED_MAIN_REPO" "git -C $UNPROTECTED_MAIN_REPO commit -m 'msg'"

	assert_allowed
}

# ── fix-ci marker (freshness window fails closed) ────────────────────────────

@test "fix-ci freshness: push under stale marker is blocked and marker is removed" {
	run_guard "$FIXCI_STALE_REPO" "git push"

	assert_blocked
	assert_absent "$FIXCI_STALE_MARKER"
}

@test "fix-ci freshness: a stat that cannot read the marker's age leaves the marker in place" {
	local repo bin
	repo=$(setup_fix_ci_repo fixci_nostat_repo feature/ci)
	bin=$(failing_stat_bin "$TMPDIR_ROOT/fixci_nostat")

	PATH="$bin:$PATH" run_guard "$repo" "git push"

	assert_present "$(marker_path "$repo")"
}

# ── fix-ci marker (scoped to the repo that raised it) ────────────────────────

@test "fix-ci scope: push -C at unmarked repo from marked cwd is blocked" {
	run_guard "$FIXCI_REPO" "git -C $REPO push"

	assert_blocked
}

@test "fix-ci scope: push at a marked repo from an unmarked cwd is allowed via -C or --git-dir" {
	each_allowed_in "$REPO" \
		"git -C $FIXCI_REPO push" \
		"git --git-dir=$FIXCI_REPO/.git push"
}

# ── Add (plan file protection) ───────────────────────────────────────────────

@test "add plan: git add explicit plan file is blocked" {
	run_guard "$PLAN_REPO" "git add .claude/plans/phase.md"

	assert_blocked
}

@test "add plan: git add . with an unstaged plan file in the tree is blocked" {
	run_guard "$UNSTAGED_PLAN_REPO" "git add ."

	assert_blocked
	assert_guard_output_includes "plan files"
}

@test "add plan: git add normal file is allowed" {
	run_guard "$REPO" "git add README"

	assert_allowed
}

# ── Subcommand detection ─────────────────────────────────────────────────────

@test "subcommand: commit behind every global-option spelling is blocked under a tdd-cycle marker" {
	each_blocked_in "$TDD_ACTIVE_REPO" \
		"git commit -m 'msg'" \
		"git -C $TDD_ACTIVE_REPO commit -m 'msg'" \
		"git --git-dir=$TDD_ACTIVE_REPO/.git commit -m 'msg'" \
		"git -c user.name=x commit -m 'msg'" \
		"git --work-tree $TDD_ACTIVE_REPO commit -m 'msg'"
}

# git rejects a -C value glued to the flag, so the command names no repo git can
# resolve: its subcommand is still recognised, but no marker is read in its place.
@test "subcommand: commit behind an attached -C value is recognised but reads no tdd-cycle marker" {
	run_guard "$TDD_ACTIVE_REPO" "git -C$TDD_ACTIVE_REPO commit -m 'msg'"

	assert_allowed
	assert_guard_output_includes "Skill(write-commit)"
}

@test "subcommand: a command line with no git word is allowed under a tdd-cycle marker" {
	each_allowed_in "$TDD_ACTIVE_REPO" \
		"echo commit" \
		"ls add"
}

@test "subcommand: a -C value that would glob onto a marked repo is taken literally and allowed" {
	run_guard "$GLOB_DIR" "git -C repo* commit -m 'msg'"

	assert_allowed
}

# ── Named repo (checks follow -C / --git-dir) ────────────────────────────────

@test "named repo: commit -C or --git-dir at a tdd-cycle repo from an unmarked cwd is blocked by its marker" {
	each_blocked_for_in "tdd-cycle-active" "$REPO" \
		"git -C $TDD_ACTIVE_REPO commit -m 'msg'" \
		"git --git-dir $TDD_ACTIVE_REPO/.git commit -m 'msg'" \
		"git --git-dir=$TDD_ACTIVE_REPO/.git commit -m 'msg'"
}

@test "named repo: commit -C at an unmarked repo from a tdd-cycle cwd is allowed" {
	run_guard "$TDD_ACTIVE_REPO" "git -C $REPO commit -m 'msg'"

	assert_allowed
}

@test "named repo: rebase -C at a dirty repo from a clean cwd is blocked as dirty" {
	run_guard "$REPO" "git -C $DIRTY_REPO rebase main"

	assert_blocked
	assert_guard_output_includes "dirty"
}

@test "named repo: rebase -C at a clean repo from a dirty cwd is allowed" {
	run_guard "$DIRTY_REPO" "git -C $REPO rebase main"

	assert_allowed
}

@test "named repo: add and commit -C at a repo holding untracked, modified, or staged plan files are blocked" {
	each_blocked_for_in "plan files matching" "$REPO" \
		"git -C $UNSTAGED_PLAN_REPO add ." \
		"git -C $MODIFIED_PLAN_REPO add ." \
		"git -C $PLAN_REPO commit -m 'msg'"
}

@test "named repo: add and commit -C at a clean repo from a cwd holding plan files are allowed" {
	each_allowed_in "$UNSTAGED_PLAN_REPO" "git -C $REPO add ."
	each_allowed_in "$MODIFIED_PLAN_REPO" "git -C $REPO add ."
	each_allowed_in "$PLAN_REPO" "git -C $REPO commit -m 'msg'"
}

@test "named repo: commit -C at a tdd-cycle repo from outside any repo is blocked by its marker" {
	each_blocked_for_in "tdd-cycle-active" "$NO_REPO_DIR" "git -C $TDD_ACTIVE_REPO commit -m 'msg'"
}

@test "named repo: commands naming no repo from outside any repo are allowed, even banned ones" {
	each_allowed_in "$NO_REPO_DIR" \
		"git commit -m 'msg'" \
		"git stash"
}

@test "named repo: a -C or --git-dir that resolves to no repo never reads the cwd's marker, dirt, or plan files" {
	each_allowed_in "$TDD_ACTIVE_REPO" \
		"git -C $ABSENT_REPO commit -m 'msg'" \
		"git --git-dir=$ABSENT_REPO/.git commit -m 'msg'" \
		"git --git-dir $ABSENT_REPO/.git commit -m 'msg'"
	each_allowed_in "$DIRTY_REPO" \
		"git -C $ABSENT_REPO rebase main" \
		"git --git-dir $ABSENT_REPO/.git rebase main"
	each_allowed_in "$UNSTAGED_PLAN_REPO" \
		"git -C $ABSENT_REPO add ." \
		"git --git-dir=$ABSENT_REPO/.git add ."
	each_allowed_in "$PLAN_REPO" \
		"git -C $ABSENT_REPO commit -m 'msg'" \
		"git --git-dir $ABSENT_REPO/.git commit -m 'msg'"
}

# ── Argument alignment (arguments read after the real subcommand) ────────────

@test "argument alignment: fix-ci deletes behind a -C value spelled like the subcommand are allowed" {
	each_allowed_in "$ALIGNED_REPO" \
		"git -C branch branch -D fix-ci/x" \
		"git -C push push origin --delete fix-ci/x" \
		"git --work-tree branch branch -D fix-ci/x" \
		"git --namespace push push origin --delete fix-ci/x"
}

@test "argument alignment: guarded arguments behind a -C value spelled like the subcommand are blocked" {
	each_blocked_in "$ALIGNED_REPO" \
		"git -C branch branch -D main" \
		"git -C push push origin --delete main"
	each_blocked_for_in "plan files matching" "$ALIGNED_REPO" "git -C add add .claude/plans/phase.md"
}

@test "argument alignment: worktree remove with no path behind -C remove is blocked as unverifiable" {
	run_guard "$ALIGNED_REPO" "git -C remove worktree remove"

	assert_blocked
	assert_guard_output_includes "unverifiable path"
}

@test "argument alignment: a non-worktree command whose -C value is remove is allowed" {
	run_guard "$ALIGNED_REPO" "git -C remove status"

	assert_allowed
}

@test "argument alignment: worktree remove of a dirty worktree behind -C worktree is blocked as dirty" {
	run_guard "$ALIGNED_REPO" "git -C worktree worktree remove $DIRTY_WT"

	assert_blocked
	assert_guard_output_includes "worktree remove (dirty)"
}

@test "argument alignment: a worktree path that would glob onto a dirty worktree is unverifiable" {
	run_guard "$WT_GLOB_REPO" "git worktree remove wt*"

	assert_blocked
	assert_guard_output_includes "unverifiable path"
	assert_guard_output_excludes "worktree remove (dirty)"
}

# ── Fixture wiring (the runners' own contract) ───────────────────────────────

# The runner call $@ fails, naming the fixture directory it was not given.
assert_refuses_missing_fixture() {
	local out exit_code=0
	out=$("$@" 2>&1) || exit_code=$?

	((exit_code != 0)) && [[ "$out" == *"fixture directory"* ]] || {
		printf 'expected a loud refusal from: %s\nexit: %d\noutput: %s\n' "$*" "$exit_code" "$out" >&2
		return 1
	}
}

@test "fixture wiring: every runner without a fixture directory refuses to run its subject" {
	assert_refuses_missing_fixture run_guard "" "git commit -m 'msg'"
	assert_refuses_missing_fixture run_tdd_guard "" "git commit -m 'msg'"
	assert_refuses_missing_fixture run_tdd_guard_read "" "src/thing.py"
	assert_refuses_missing_fixture run_script "" git status
}
