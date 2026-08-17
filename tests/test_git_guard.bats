#!/usr/bin/env bats

load helpers/hooks

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

	export FIXCI_REPO
	FIXCI_REPO=$(setup_fix_ci_repo fixci_repo feature/ci)

	export FIXCI_MAIN_REPO
	FIXCI_MAIN_REPO=$(setup_fix_ci_repo fixci_main_repo main)

	export FIXCI_MASTER_REPO
	FIXCI_MASTER_REPO=$(setup_fix_ci_repo fixci_master_repo master)

	export FIXCI_DETACHED_REPO
	FIXCI_DETACHED_REPO=$(setup_fix_ci_repo fixci_detached_repo feature/ci)
	git -C "$FIXCI_DETACHED_REPO" switch --detach --quiet HEAD

	export FIXCI_STALE_REPO
	FIXCI_STALE_REPO=$(setup_fix_ci_repo fixci_stale_repo feature/ci)
	export FIXCI_STALE_MARKER
	FIXCI_STALE_MARKER=$(marker_path "$FIXCI_STALE_REPO")
	backdate_marker "$FIXCI_STALE_REPO" "$STALE_OFFSET_MINUTES"

	export FIXCI_FUTURE_REPO
	FIXCI_FUTURE_REPO=$(setup_fix_ci_repo fixci_future_repo feature/ci)
	backdate_marker "$FIXCI_FUTURE_REPO" "$FUTURE_OFFSET_MINUTES"
}

teardown_file() {
	[[ -n "$TMPDIR_ROOT" ]] && rm -rf "$TMPDIR_ROOT"
}

# ── Push ─────────────────────────────────────────────────────────────────────

@test "push: git push origin main is blocked" {
	run_guard "$REPO" "git push origin main"
	assert_blocked
}

@test "push: git push --force is blocked" {
	run_guard "$REPO" "git push --force"
	assert_blocked
}

@test "push: git push -u origin HEAD is blocked" {
	run_guard "$REPO" "git push -u origin HEAD"
	assert_blocked
}

# ── Checkout (discard) ───────────────────────────────────────────────────────

@test "checkout: git checkout -- file is blocked" {
	run_guard "$REPO" "git checkout -- file"
	assert_blocked
}

@test "checkout: git checkout HEAD -- file is blocked" {
	run_guard "$REPO" "git checkout HEAD -- file"
	assert_blocked
}

@test "checkout: git checkout . is blocked" {
	run_guard "$REPO" "git checkout ."
	assert_blocked
}

@test "checkout: git checkout -f branch is blocked" {
	run_guard "$REPO" "git checkout -f branch"
	assert_blocked
}

@test "checkout: git checkout --force branch is blocked" {
	run_guard "$REPO" "git checkout --force branch"
	assert_blocked
}

@test "checkout: git checkout branch is blocked" {
	run_guard "$REPO" "git checkout branch"
	assert_blocked
}

@test "checkout: git checkout -b new-branch is blocked" {
	run_guard "$REPO" "git checkout -b new-branch"
	assert_blocked
}

@test "checkout: git checkout -b feat/my.feature is blocked" {
	run_guard "$REPO" "git checkout -b feat/my.feature"
	assert_blocked
}

# ── Switch (discard) ─────────────────────────────────────────────────────────

@test "switch: git switch -f branch is blocked" {
	run_guard "$REPO" "git switch -f branch"
	assert_blocked
}

@test "switch: git switch --force branch is blocked" {
	run_guard "$REPO" "git switch --force branch"
	assert_blocked
}

@test "switch: git switch --discard-changes is blocked" {
	run_guard "$REPO" "git switch --discard-changes branch"
	assert_blocked
}

@test "switch: git switch branch is allowed" {
	run_guard "$REPO" "git switch branch"
	assert_allowed
}

@test "switch: git switch -c new-branch is allowed" {
	run_guard "$REPO" "git switch -c new-branch"
	assert_allowed
}

# ── Reset ────────────────────────────────────────────────────────────────────

@test "reset: git reset is blocked" {
	run_guard "$REPO" "git reset"
	assert_blocked
}

@test "reset: git reset HEAD is blocked" {
	run_guard "$REPO" "git reset HEAD"
	assert_blocked
}

@test "reset: git reset --soft HEAD~1 is blocked" {
	run_guard "$REPO" "git reset --soft HEAD~1"
	assert_blocked
}

@test "reset: git reset --hard is blocked" {
	run_guard "$REPO" "git reset --hard"
	assert_blocked
}

# ── Clean ────────────────────────────────────────────────────────────────────

@test "clean: git clean -f is blocked" {
	run_guard "$REPO" "git clean -f"
	assert_blocked
}

@test "clean: git clean -fd is blocked" {
	run_guard "$REPO" "git clean -fd"
	assert_blocked
}

@test "clean: git clean -fdx is blocked" {
	run_guard "$REPO" "git clean -fdx"
	assert_blocked
}

@test "clean: git clean -n is allowed" {
	run_guard "$REPO" "git clean -n"
	assert_allowed
}

@test "clean: git clean --dry-run is allowed" {
	run_guard "$REPO" "git clean --dry-run"
	assert_allowed
}

# ── Stash ────────────────────────────────────────────────────────────────────

@test "stash: git stash is blocked" {
	run_guard "$REPO" "git stash"
	assert_blocked
}

@test "stash: git stash push is blocked" {
	run_guard "$REPO" "git stash push"
	assert_blocked
}

@test "stash: git stash list is blocked" {
	run_guard "$REPO" "git stash list"
	assert_blocked
}

@test "stash: git stash pop is blocked" {
	run_guard "$REPO" "git stash pop"
	assert_blocked
}

# ── Branch ───────────────────────────────────────────────────────────────────

@test "branch: git branch -D feature is blocked" {
	run_guard "$REPO" "git branch -D feature"
	assert_blocked
}

@test "branch: git branch -d feature is allowed" {
	run_guard "$REPO" "git branch -d feature"
	assert_allowed
}

@test "branch: git branch -a is allowed" {
	run_guard "$REPO" "git branch -a"
	assert_allowed
}

@test "branch: git branch new-branch is allowed" {
	run_guard "$REPO" "git branch new-branch"
	assert_allowed
}

# ── Restore ──────────────────────────────────────────────────────────────────

@test "restore: git restore file is blocked" {
	run_guard "$REPO" "git restore file"
	assert_blocked
}

@test "restore: git restore . is blocked" {
	run_guard "$REPO" "git restore ."
	assert_blocked
}

@test "restore: git restore --staged file is allowed" {
	run_guard "$REPO" "git restore --staged file"
	assert_allowed
}

@test "restore: git restore --staged . is allowed" {
	run_guard "$REPO" "git restore --staged ."
	assert_allowed
}

@test "restore: git restore -W file is blocked" {
	run_guard "$REPO" "git restore -W file"
	assert_blocked
}

@test "restore: git restore --worktree file is blocked" {
	run_guard "$REPO" "git restore --worktree file"
	assert_blocked
}

@test "restore: git restore --staged --worktree file is blocked" {
	run_guard "$REPO" "git restore --staged --worktree file"
	assert_blocked
}

@test "restore: git restore --staged -W file is blocked" {
	run_guard "$REPO" "git restore --staged -W file"
	assert_blocked
}

# ── Rm ───────────────────────────────────────────────────────────────────────

@test "rm: git rm file is blocked" {
	run_guard "$REPO" "git rm file"
	assert_blocked
}

@test "rm: git rm -r dir is blocked" {
	run_guard "$REPO" "git rm -r dir/"
	assert_blocked
}

@test "rm: git rm -f file is blocked" {
	run_guard "$REPO" "git rm -f file"
	assert_blocked
}

@test "rm: git rm --cached file is allowed" {
	run_guard "$REPO" "git rm --cached file"
	assert_allowed
}

@test "rm: git rm -n file is allowed" {
	run_guard "$REPO" "git rm -n file"
	assert_allowed
}

@test "rm: git rm --dry-run file is allowed" {
	run_guard "$REPO" "git rm --dry-run file"
	assert_allowed
}

@test "rm: git rm -rn dir is allowed" {
	run_guard "$REPO" "git rm -rn dir/"
	assert_allowed
}

# ── Reflog / prune ───────────────────────────────────────────────────────────

@test "reflog: git reflog expire is blocked" {
	run_guard "$REPO" "git reflog expire"
	assert_blocked
}

@test "reflog: git reflog delete is blocked" {
	run_guard "$REPO" "git reflog delete"
	assert_blocked
}

@test "reflog: git prune is blocked" {
	run_guard "$REPO" "git prune"
	assert_blocked
}

@test "reflog: git gc --prune=now is blocked" {
	run_guard "$REPO" "git gc --prune=now"
	assert_blocked
}

@test "reflog: git gc --prune=2.weeks.ago is blocked" {
	run_guard "$REPO" "git gc --prune=2.weeks.ago"
	assert_blocked
}

@test "reflog: git gc is allowed" {
	run_guard "$REPO" "git gc"
	assert_allowed
}

@test "reflog: git reflog is allowed" {
	run_guard "$REPO" "git reflog"
	assert_allowed
}

@test "reflog: git reflog show is allowed" {
	run_guard "$REPO" "git reflog show"
	assert_allowed
}

# ── Commit ───────────────────────────────────────────────────────────────────

@test "commit: git commit --amend is blocked" {
	run_guard "$REPO" "git commit --amend"
	assert_blocked
}

@test "commit: git commit -m msg is allowed" {
	run_guard "$REPO" "git commit -m 'msg'"
	assert_allowed
}

@test "commit: git commit with plan files staged is blocked" {
	run_guard "$PLAN_REPO" "git commit -m 'msg'"
	assert_blocked
}

# ── --no-verify (any subcommand) ─────────────────────────────────────────────

@test "no-verify: git commit --no-verify is blocked" {
	run_guard "$REPO" "git commit --no-verify -m 'msg'"
	assert_blocked
}

@test "no-verify: git push --no-verify is blocked" {
	run_guard "$REPO" "git push --no-verify"
	assert_blocked
}

# ── fix-ci marker (append-only push relaxed) ─────────────────────────────────

@test "fix-ci: push under marker is allowed" {
	run_guard "$FIXCI_REPO" "git push"
	assert_allowed
}

@test "fix-ci: push on main under marker is allowed" {
	run_guard "$FIXCI_MAIN_REPO" "git push"
	assert_allowed
}

@test "fix-ci: push on master under marker is allowed" {
	run_guard "$FIXCI_MASTER_REPO" "git push"
	assert_allowed
}

@test "fix-ci: push with detached HEAD under marker is allowed" {
	run_guard "$FIXCI_DETACHED_REPO" "git push"
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

@test "fix-ci: push --delete of non-fix-ci branch under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push origin --delete main"
	assert_blocked
}

@test "fix-ci: push :main (delete refspec) under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push origin :main"
	assert_blocked
}

@test "fix-ci: push --mirror under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push --mirror"
	assert_blocked
}

@test "fix-ci: push --force-with-lease under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push --force-with-lease"
	assert_blocked
}

@test "fix-ci: push --force under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push --force"
	assert_blocked
}

@test "fix-ci: push -f under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push -f"
	assert_blocked
}

@test "fix-ci: push -fu (bundled force) under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push -fu origin HEAD"
	assert_blocked
}

@test "fix-ci: push -uf (f-last cluster) under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push -uf origin HEAD"
	assert_blocked
}

@test "fix-ci: push +refspec (force) under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push origin +main:main"
	assert_blocked
}

@test "fix-ci: amend under marker is blocked" {
	run_guard "$FIXCI_REPO" "git commit --amend"
	assert_blocked
}

@test "fix-ci: branch -D fix-ci/* under marker is allowed" {
	run_guard "$FIXCI_REPO" "git branch -D fix-ci/lint"
	assert_allowed
}

@test "fix-ci: branch -D other branch under marker is blocked" {
	run_guard "$FIXCI_REPO" "git branch -D feature"
	assert_blocked
}

@test "fix-ci: branch -D mixed fix-ci/* and other under marker is blocked" {
	run_guard "$FIXCI_REPO" "git branch -D fix-ci/lint feature"
	assert_blocked
}

@test "fix-ci: branch -D with no names under marker is blocked" {
	run_guard "$FIXCI_REPO" "git branch -D"
	assert_blocked
}

@test "fix-ci: commit --no-verify under marker is blocked" {
	run_guard "$FIXCI_REPO" "git commit --no-verify -m 'msg'"
	assert_blocked
}

@test "fix-ci: push --no-verify under marker is blocked" {
	run_guard "$FIXCI_REPO" "git push --no-verify"
	assert_blocked
}

# ── fix-ci marker (freshness window fails closed) ────────────────────────────

@test "fix-ci freshness: push under stale marker is blocked and marker is removed" {
	run_guard "$FIXCI_STALE_REPO" "git push"
	assert_blocked
	assert_absent "$FIXCI_STALE_MARKER"
}

@test "fix-ci freshness: push under future-dated marker is blocked" {
	run_guard "$FIXCI_FUTURE_REPO" "git push"
	assert_blocked
}

# ── fix-ci marker (scoped to the repo that raised it) ────────────────────────

@test "fix-ci scope: push -C at unmarked repo from marked cwd is blocked" {
	run_guard "$FIXCI_REPO" "git -C $REPO push"
	assert_blocked
}

@test "fix-ci scope: push -C at marked repo from unmarked cwd is allowed" {
	run_guard "$REPO" "git -C $FIXCI_REPO push"
	assert_allowed
}

@test "fix-ci scope: push --git-dir at marked repo from unmarked cwd is allowed" {
	run_guard "$REPO" "git --git-dir=$FIXCI_REPO/.git push"
	assert_allowed
}

# ── History extraction with redirect ─────────────────────────────────────────

@test "history redirect: git show > file is blocked" {
	run_guard "$REPO" "git show HEAD > output.txt"
	assert_blocked
}

@test "history redirect: git cat-file > file is blocked" {
	run_guard "$REPO" "git cat-file blob HEAD:README > out"
	assert_blocked
}

@test "history redirect: git show 2>file (stderr only) is allowed" {
	run_guard "$REPO" "git show HEAD 2>errors.txt"
	assert_allowed
}

# ── Apply reverse ────────────────────────────────────────────────────────────

@test "apply: git apply -R is blocked" {
	run_guard "$REPO" "git apply -R patch.diff"
	assert_blocked
}

@test "apply: git apply --reverse is blocked" {
	run_guard "$REPO" "git apply --reverse patch.diff"
	assert_blocked
}

@test "apply: git apply patch is allowed" {
	run_guard "$REPO" "git apply patch.diff"
	assert_allowed
}

# ── Add (force-add) ──────────────────────────────────────────────────────────

@test "add force: git add -f file is blocked" {
	run_guard "$REPO" "git add -f some-file"
	assert_blocked
}

@test "add force: git add --force file is blocked" {
	run_guard "$REPO" "git add --force some-file"
	assert_blocked
}

@test "add force: git add -f . is blocked" {
	run_guard "$REPO" "git add -f ."
	assert_blocked
}

@test "add force: git add --force -A is blocked" {
	run_guard "$REPO" "git add --force -A"
	assert_blocked
}

# ── Add (plan file protection) ───────────────────────────────────────────────

@test "add plan: git add explicit plan file is blocked" {
	run_guard "$PLAN_REPO" "git add .claude/plans/phase.md"
	assert_blocked
}

@test "add plan: git add normal file is allowed" {
	run_guard "$REPO" "git add README"
	assert_allowed
}

# ── Chained commands ─────────────────────────────────────────────────────────

@test "chain: add then checkout discard is blocked" {
	run_guard "$REPO" "git add . && git checkout -- ."
	assert_blocked
}

@test "chain: push in chain is blocked" {
	run_guard "$REPO" "git status && git push origin main"
	assert_blocked
}

@test "chain: stash in chain with semicolon is blocked" {
	run_guard "$REPO" "git status; git stash"
	assert_blocked
}

# ── Safe commands (never block) ──────────────────────────────────────────────

@test "safe: git status is allowed" {
	run_guard "$REPO" "git status"
	assert_allowed
}

@test "safe: git log is allowed" {
	run_guard "$REPO" "git log --oneline -10"
	assert_allowed
}

@test "safe: git diff is allowed" {
	run_guard "$REPO" "git diff"
	assert_allowed
}

@test "safe: git fetch is allowed" {
	run_guard "$REPO" "git fetch origin"
	assert_allowed
}

@test "safe: git pull is allowed" {
	run_guard "$REPO" "git pull"
	assert_allowed
}

@test "safe: git merge is allowed" {
	run_guard "$REPO" "git merge main"
	assert_allowed
}

@test "safe: git add . is allowed" {
	run_guard "$REPO" "git add ."
	assert_allowed
}
