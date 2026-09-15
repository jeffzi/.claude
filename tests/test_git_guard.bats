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

	export IGNORED_REPO
	IGNORED_REPO=$(setup_repo ignored_repo)
	printf 'build/\n' >"$IGNORED_REPO/.gitignore"
	git -C "$IGNORED_REPO" add .gitignore
	git -C "$IGNORED_REPO" -c commit.gpgsign=false commit -q -m "ignore build"
	mkdir -p "$IGNORED_REPO/build"
	touch "$IGNORED_REPO/build/out.js"

	export DIRTY_REPO
	DIRTY_REPO=$(setup_repo dirty_repo)
	printf 'uncommitted\n' >>"$DIRTY_REPO/README"

	export TDD_ACTIVE_REPO
	TDD_ACTIVE_REPO=$(setup_repo tdd_active_repo)
	touch "$(git -C "$TDD_ACTIVE_REPO" rev-parse --absolute-git-dir)/tdd-cycle-active"

	export WT_REPO
	WT_REPO=$(setup_repo wt_repo)

	export CLEAN_WT
	CLEAN_WT=$(add_worktree "$WT_REPO" clean)

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

	export RELEASE_MARKED_REPO
	RELEASE_MARKED_REPO=$(setup_release_marked_repo release_marked_repo)

	export RELEASE_STALE_REPO
	RELEASE_STALE_REPO=$(setup_release_marked_repo release_stale_repo)
	backdate_release_marker "$RELEASE_STALE_REPO" "$STALE_OFFSET_MINUTES"

	export RELEASE_FUTURE_REPO
	RELEASE_FUTURE_REPO=$(setup_release_marked_repo release_future_repo)
	backdate_release_marker "$RELEASE_FUTURE_REPO" "$FUTURE_OFFSET_MINUTES"

	export RELEASE_FIXCI_REPO
	RELEASE_FIXCI_REPO=$(setup_fix_ci_repo release_fixci_repo feature/ci)
	raise_release_marker "$RELEASE_FIXCI_REPO"

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

	export WT_NAMED_DIRTY_REPO
	WT_NAMED_DIRTY_REPO=$(setup_repo wt_named_dirty_repo)
	git -C "$WT_NAMED_DIRTY_REPO" worktree add -q -b wt-named "$WT_NAMED_DIRTY_REPO/wt1"
	printf 'uncommitted\n' >>"$WT_NAMED_DIRTY_REPO/wt1/README"

	export WT_NAMED_CLEAN_REPO
	WT_NAMED_CLEAN_REPO=$(setup_repo wt_named_clean_repo)
	git -C "$WT_NAMED_CLEAN_REPO" worktree add -q -b wt-named "$WT_NAMED_CLEAN_REPO/wt1"
}

# Repo with a tdd-cycle marker raised; prints the repo dir.
setup_tdd_active_repo() {
	local dir
	dir=$(setup_repo "$1")
	touch "$(git -C "$dir" rev-parse --absolute-git-dir)/tdd-cycle-active"
	printf '%s' "$dir"
}

# Leave an untracked plan file in the repo at $1.
add_untracked_plan() {
	mkdir -p "$1/.claude/plans"
	printf 'plan content\n' >"$1/.claude/plans/phase.md"
}

# Repo with a fresh release marker raised; prints the repo dir.
setup_release_marked_repo() {
	local dir
	dir=$(setup_repo "$1")
	raise_release_marker "$dir"
	printf '%s' "$dir"
}

teardown_file() {
	cleanup_tmpdir_root
}

# Every command in the list is blocked in repo $1; a failure names the command.
each_blocked_in() {
	local dir="$1" cmd
	shift
	for cmd in "$@"; do
		run_guard "$dir" "$cmd"
		assert_blocked || {
			printf 'command: %s\n' "$cmd" >&2
			return 1
		}
	done
}

# Every command in the list is blocked in repo $2 with output naming reason $1;
# a failure names the command.
each_blocked_for_in() {
	local reason="$1" dir="$2" cmd
	shift 2
	for cmd in "$@"; do
		run_guard "$dir" "$cmd"
		{ assert_blocked && assert_guard_output_includes "$reason"; } || {
			printf 'command: %s\n' "$cmd" >&2
			return 1
		}
	done
}

# Every command in the list is allowed in repo $1; a failure names the command.
each_allowed_in() {
	local dir="$1" cmd
	shift
	for cmd in "$@"; do
		run_guard "$dir" "$cmd"
		assert_allowed || {
			printf 'command: %s\n' "$cmd" >&2
			return 1
		}
	done
}

# run_guard on the command read from stdin — for commands that embed their own
# nested heredoc, which a bats argument cannot spell directly.
run_guard_heredoc() {
	local cmd
	cmd=$(cat)
	run_guard "$REPO" "$cmd"
}

# ── Push ─────────────────────────────────────────────────────────────────────

@test "push: every push form is blocked without a marker" {
	each_blocked_in "$REPO" \
		"git push origin main" \
		"git push --force" \
		"git push -u origin HEAD"
}

# ── Checkout (banned outright) ───────────────────────────────────────────────

@test "checkout: every form is blocked" {
	each_blocked_in "$REPO" \
		"git checkout -- file" \
		"git checkout HEAD -- file" \
		"git checkout ." \
		"git checkout -f branch" \
		"git checkout --force branch" \
		"git checkout branch" \
		"git checkout -b new-branch"
}

# ── Switch (discard) ─────────────────────────────────────────────────────────

@test "switch: every force form is blocked" {
	each_blocked_in "$REPO" \
		"git switch -f branch" \
		"git switch --force branch" \
		"git switch --discard-changes branch"
}

@test "switch: a plain switch and switch -c are allowed" {
	each_allowed_in "$REPO" \
		"git switch branch" \
		"git switch -c new-branch"
}

# ── Reset ────────────────────────────────────────────────────────────────────

@test "reset: every form is blocked" {
	each_blocked_in "$REPO" \
		"git reset" \
		"git reset HEAD" \
		"git reset --soft HEAD~1" \
		"git reset --hard"
}

# ── Clean ────────────────────────────────────────────────────────────────────

@test "clean: every form carrying -f is blocked" {
	each_blocked_in "$REPO" \
		"git clean -f" \
		"git clean -fd" \
		"git clean -fdx"
}

@test "clean: dry runs are allowed" {
	each_allowed_in "$REPO" \
		"git clean -n" \
		"git clean --dry-run"
}

# ── Stash ────────────────────────────────────────────────────────────────────

@test "stash: every form is blocked" {
	each_blocked_in "$REPO" \
		"git stash" \
		"git stash push" \
		"git stash list" \
		"git stash pop"
}

# ── Branch ───────────────────────────────────────────────────────────────────

@test "branch: branch -D is blocked without a marker, whatever the branch" {
	each_blocked_in "$REPO" \
		"git branch -D feature" \
		"git branch -D plan/x"
}

@test "branch: -d, -a, and creating a branch are allowed" {
	each_allowed_in "$REPO" \
		"git branch -d feature" \
		"git branch -a" \
		"git branch new-branch"
}

# ── Worktree ─────────────────────────────────────────────────────────────────

@test "worktree: remove of a clean worktree is allowed" {
	run_guard "$WT_REPO" "git worktree remove $CLEAN_WT"

	assert_allowed
}

@test "worktree: remove of a dirty worktree is blocked" {
	run_guard "$WT_REPO" "git worktree remove $DIRTY_WT"

	assert_blocked
}

@test "worktree: remove --force of a clean worktree is blocked" {
	run_guard "$WT_REPO" "git worktree remove --force $CLEAN_WT"

	assert_blocked
}

@test "worktree: remove with a short force flag, alone or bundled, is blocked" {
	each_blocked_in "$WT_REPO" \
		"git worktree remove -f $CLEAN_WT" \
		"git worktree remove -fv $CLEAN_WT"
}

@test "worktree: remove of a path the guard cannot verify is blocked" {
	# shellcheck disable=SC2016
	each_blocked_in "$WT_REPO" \
		'git worktree remove "$wt"' \
		"git worktree remove" \
		"git worktree remove $TMPDIR_ROOT/absent"
}

@test "worktree: remove --force in a for loop over quoted paths is blocked" {
	# shellcheck disable=SC2016
	run_guard "$WT_REPO" 'for wt in .claude/worktrees/a .claude/worktrees/b; do git worktree unlock "$wt" 2>/dev/null; git worktree remove --force "$wt"; done'

	assert_blocked
}

@test "worktree: remove -C of a relative path to a dirty worktree in the named repo is blocked as dirty" {
	run_guard "$REPO" "git -C $WT_NAMED_DIRTY_REPO worktree remove wt1"

	assert_blocked
	assert_guard_output_includes "worktree remove (dirty)"
}

@test "worktree: remove -C of a relative path to a clean worktree in the named repo is allowed from a cwd holding a dirty one" {
	run_guard "$WT_GLOB_REPO" "git -C $WT_NAMED_CLEAN_REPO worktree remove wt1"

	assert_allowed
}

@test "worktree: remove -C of a relative path absent from the named repo is unverifiable even when the cwd holds it" {
	run_guard "$WT_NAMED_CLEAN_REPO" "git -C $REPO worktree remove wt1"

	assert_blocked
	assert_guard_output_includes "unverifiable path"
}

@test "worktree: remove -C of an absolute path to a clean worktree is allowed" {
	run_guard "$REPO" "git -C $WT_REPO worktree remove $CLEAN_WT"

	assert_allowed
}

@test "worktree: remove of a relative path to a clean worktree without -C is allowed" {
	run_guard "$WT_REPO" "git worktree remove .claude/worktrees/clean"

	assert_allowed
}

@test "worktree: remove of a relative path behind relative or chained -C values resolves the way git does" {
	each_blocked_for_in "worktree remove (dirty)" "$TMPDIR_ROOT" \
		"git -C wt_named_dirty_repo worktree remove wt1"
	each_blocked_for_in "worktree remove (dirty)" "$REPO" \
		"git -C $TMPDIR_ROOT -C wt_named_dirty_repo worktree remove wt1" \
		"git -C wt_named_clean_repo -C $WT_NAMED_DIRTY_REPO worktree remove wt1" \
		"git -C $TMPDIR_ROOT --git-dir elsewhere/.git -C wt_named_dirty_repo worktree remove wt1"
}

@test "worktree: list, add, unlock, and prune are allowed" {
	# shellcheck disable=SC2016
	each_allowed_in "$WT_REPO" \
		"git worktree list" \
		"git worktree add $TMPDIR_ROOT/added-wt" \
		'git worktree unlock "$wt"' \
		"git worktree prune"
}

# ── Restore ──────────────────────────────────────────────────────────────────

@test "restore: restore without --staged is blocked" {
	each_blocked_in "$REPO" \
		"git restore file" \
		"git restore ."
}

@test "restore: restore --staged is allowed" {
	each_allowed_in "$REPO" \
		"git restore --staged file" \
		"git restore --staged ."
}

@test "restore: any worktree flag is blocked even beside --staged" {
	each_blocked_in "$REPO" \
		"git restore -W file" \
		"git restore --worktree file" \
		"git restore --staged --worktree file" \
		"git restore --staged -W file"
}

@test "restore: --staged text inside a global option value does not allow the restore" {
	each_blocked_in "$REPO" \
		"git -C x--staged restore ." \
		"git -c a.b=--staged restore ." \
		"git --namespace --staged restore ."
}

# ── Rm ───────────────────────────────────────────────────────────────────────

@test "rm: rm that touches the working tree is blocked" {
	each_blocked_in "$REPO" \
		"git rm file" \
		"git rm -r dir/" \
		"git rm -f file"
}

@test "rm: --cached and every dry-run spelling are allowed" {
	each_allowed_in "$REPO" \
		"git rm --cached file" \
		"git rm -n file" \
		"git rm --dry-run file" \
		"git rm -rn dir/"
}

@test "rm: --cached or dry-run text inside a global option value does not allow the rm" {
	each_blocked_in "$REPO" \
		"git -C --cached rm file" \
		"git --namespace --cached rm file" \
		"git -c a.b=--dry-run rm file" \
		"git -Cn rm file"
}

# ── Reflog / prune ───────────────────────────────────────────────────────────

@test "reflog: expire and delete are blocked" {
	each_blocked_in "$REPO" \
		"git reflog expire" \
		"git reflog delete"
}

@test "reflog: git prune is blocked" {
	run_guard "$REPO" "git prune"

	assert_blocked
}

@test "reflog: gc with an immediate prune is blocked" {
	each_blocked_in "$REPO" \
		"git gc --prune=now" \
		"git gc --prune=2.weeks.ago"
}

@test "reflog: plain gc and reading the reflog are allowed" {
	each_allowed_in "$REPO" \
		"git gc" \
		"git reflog" \
		"git reflog show"
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

# ── --no-verify (any subcommand) ─────────────────────────────────────────────

@test "no-verify: --no-verify on any subcommand is blocked" {
	each_blocked_in "$REPO" \
		"git commit --no-verify -m 'msg'" \
		"git push --no-verify"
}

# ── Rebase ───────────────────────────────────────────────────────────────────

@test "rebase: rebasing with uncommitted changes is blocked" {
	run_guard "$DIRTY_REPO" "git rebase main"

	assert_blocked
	assert_guard_output_includes "dirty"
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

# ── release.sh (user-run) ────────────────────────────────────────────────────

@test "release: invoking the script without a marker is blocked as user-run" {
	# shellcheck disable=SC2088 # the literal tilde is the command under test, not a path this file expands
	run_guard "$REPO" "~/.claude/scripts/release.sh merge"

	assert_blocked
	assert_guard_output_includes "release.sh"
	assert_guard_output_includes "only through /release"
}

@test "release: every quoting, path, and interpreter spelling of the invocation is blocked" {
	# shellcheck disable=SC2088
	each_blocked_in "$REPO" \
		"release.sh merge" \
		"./scripts/release.sh merge" \
		"bash scripts/release.sh merge" \
		'bash "scripts/release.sh"' \
		'"~/.claude/scripts/release.sh" merge' \
		"/bin/bash scripts/release.sh" \
		"/usr/bin/env bash scripts/release.sh" \
		"env release.sh merge" \
		"command bash scripts/release.sh" \
		"exec scripts/release.sh" \
		"FOO=1 scripts/release.sh"
}

@test "release: the invocation is found behind every fragment boundary" {
	local heredoc
	heredoc=$(
		cat <<'CMD'
git commit -m "$(cat <<'EOF'
docs: describe how the plan branch lands
EOF
)" && "scripts/release.sh"
CMD
	)
	# shellcheck disable=SC2088
	each_blocked_in "$REPO" \
		'git commit -m "line one
line two" && bash ~/.claude/scripts/release.sh' \
		'cd /tmp
~/.claude/scripts/release.sh' \
		'git status
bash scripts/release.sh merge' \
		'echo a&"&b" ; bash scripts/release.sh' \
		'git status && "scripts/release.sh"' \
		"$heredoc"
}

@test "release: a message that merely names the script is allowed in every quoting" {
	each_allowed_in "$REPO" \
		'git commit -m "document release.sh"' \
		"git commit -m 'document release.sh'" \
		'git commit -m "notes
release.sh is user-run" && git status' \
		"git commit -m 'notes
release.sh is user-run' && git status"
}

@test "release: a message naming the script with a subcommand is allowed" {
	each_allowed_in "$REPO" \
		'git commit -m "docs: explain release.sh merge"' \
		"git commit -m 'docs: explain release.sh finish'"
}

@test "release: a heredoc-fed commit message naming the script with a subcommand is allowed" {
	run_guard_heredoc <<'CMD'
git commit -m "$(cat <<'EOF'
docs: explain how release.sh finish tags the release
EOF
)"
CMD

	assert_allowed
}

@test "release: reading, linting, formatting, chmod, and bats on the script are allowed" {
	each_allowed_in "$REPO" \
		"cat scripts/release.sh" \
		"shellcheck -x scripts/release.sh" \
		"shfmt -d scripts/release.sh" \
		"chmod +x scripts/release.sh" \
		"bats tests/test_release.bats"
}

@test "release: the status subcommand needs no marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$REPO" \
		"~/.claude/scripts/release.sh status" \
		"bash scripts/release.sh status" \
		"release.sh status"
}

@test "release: status past the first argument does not exempt the invocation" {
	each_blocked_in "$REPO" \
		"release.sh merge status" \
		"bash scripts/release.sh --skip-ci status"
}

@test "release: a subcommand makes it an invocation whatever words precede it" {
	# shellcheck disable=SC2088
	each_blocked_for_in "only through /release" "$REPO" \
		"timeout 5 scripts/release.sh merge" \
		"xargs release.sh merge" \
		"uv run release.sh merge" \
		"uv run ~/.claude/scripts/release.sh finish --check" \
		"nice -n 5 release.sh start 1.2.0"
}

@test "release: status behind a preceding word still needs no marker" {
	each_allowed_in "$REPO" \
		"timeout 5 release.sh status" \
		"uv run scripts/release.sh status"
}

@test "release: an invocation behind a preceding word is allowed under a fresh marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$RELEASE_MARKED_REPO" \
		"timeout 5 scripts/release.sh merge" \
		"uv run ~/.claude/scripts/release.sh finish --check" \
		"nice -n 5 release.sh start 1.2.0"
}

@test "release: every invocation spelling is allowed under a fresh marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$RELEASE_MARKED_REPO" \
		"~/.claude/scripts/release.sh" \
		"bash scripts/release.sh merge" \
		'"~/.claude/scripts/release.sh" merge'
}

@test "release: invoking the script under a stale or future-dated marker is blocked" {
	local dir
	for dir in "$RELEASE_STALE_REPO" "$RELEASE_FUTURE_REPO"; do
		run_guard "$dir" "bash scripts/release.sh merge"

		if ! assert_blocked || ! assert_guard_output_includes "only through /release"; then
			printf 'repo: %s\n' "$dir" >&2
			return 1
		fi
	done
}

@test "release: force-with-lease under the release marker alone is blocked as an unsanctioned push" {
	run_guard "$RELEASE_MARKED_REPO" "git push --force-with-lease"

	assert_blocked
	assert_guard_output_includes "Automatic git push is not allowed"
}

@test "release: force-with-lease under both markers is blocked as a history rewrite" {
	run_guard "$RELEASE_FIXCI_REPO" "git push --force-with-lease"

	assert_blocked
	assert_guard_output_includes "never rewrites history"
}

# ── Shared constants ─────────────────────────────────────────────────────────

@test "shared constant: branch-policy.sh exposes the release marker file and config key" {
	local want="release-active release" got

	got=$(bash -c '. "$1"; printf "%s %s" "$RELEASE_MARKER" "$RELEASE_KEY"' _ "$BRANCH_POLICY_LIB")

	[[ "$got" == "$want" ]] || {
		printf 'RELEASE_MARKER/RELEASE_KEY are "%s", expected "%s"\n' "$got" "$want" >&2
		return 1
	}
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

# ── History extraction with redirect ─────────────────────────────────────────

@test "history redirect: show or cat-file with stdout redirected to a file is blocked" {
	each_blocked_in "$REPO" \
		"git show HEAD > output.txt" \
		"git cat-file blob HEAD:README > out"
}

@test "history redirect: git show 2>file (stderr only) is allowed" {
	run_guard "$REPO" "git show HEAD 2>errors.txt"

	assert_allowed
}

# ── Apply reverse ────────────────────────────────────────────────────────────

@test "apply: reverse application is blocked in both spellings" {
	each_blocked_in "$REPO" \
		"git apply -R patch.diff" \
		"git apply --reverse patch.diff"
}

@test "apply: git apply patch is allowed" {
	run_guard "$REPO" "git apply patch.diff"

	assert_allowed
}

# ── Add (force-add) ──────────────────────────────────────────────────────────

@test "add force: every force-add spelling is blocked" {
	each_blocked_in "$REPO" \
		"git add -f some-file" \
		"git add --force some-file" \
		"git add -f ." \
		"git add --force -A"
}

# ── Add (gitignored paths) ───────────────────────────────────────────────────

@test "add ignored: adding a gitignored path is blocked naming the rule" {
	run_guard "$IGNORED_REPO" "git add build/out.js"

	assert_blocked
	assert_guard_output_includes "gitignore"
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

# ── Chained commands ─────────────────────────────────────────────────────────

@test "chain: a banned command after && is blocked" {
	each_blocked_in "$REPO" \
		"git add . && git checkout -- ." \
		"git status && git push origin main"
}

@test "chain: stash in chain with semicolon is blocked" {
	run_guard "$REPO" "git status; git stash"

	assert_blocked
}

@test "chain: banned command after semicolon following a quoted message is blocked" {
	run_guard "$REPO" "git commit -m \"msg\"; git reset --hard"

	assert_blocked
}

# ── Quoted text and heredoc bodies (not command position) ────────────────────

@test "quoting: banned commands and separators inside a quoted argument are allowed" {
	each_allowed_in "$REPO" \
		"git commit -m \"docs: use git switch; git checkout is on the deny list\"" \
		"echo 'never run this; git reset --hard'" \
		"git commit -m \"fix: handle a && b in parser; git clean -fd is now documented\""
}

@test "quoting: history redirect named in a heredoc body is allowed" {
	local cmd
	cmd=$(
		cat <<'CMD'
git commit -m "$(cat <<'EOF'
docs: warn that git show HEAD:f 1> f overwrites the working file
EOF
)"
CMD
	)
	run_guard "$REPO" "$cmd"

	assert_allowed
}

@test "heredoc: a body fed to a consumer that only reads it is not scanned" {
	each_allowed_in "$REPO" \
		"git commit -F - <<'EOF'
release.sh merge lands the branch
EOF" \
		"git commit -F - <<EOF
then git reset --hard is forbidden
EOF" \
		"cat <<EOF > notes.txt
git push --force
EOF" \
		"gh pr create --body-file - <<\"EOF\"
git push --force is never run here
EOF" \
		"tee notes.txt <<-EOF
release.sh merge
EOF"
}

@test "heredoc: a body fed to a consumer that could execute it is scanned" {
	each_blocked_in "$REPO" \
		"bash <<'EOF'
git push --force
EOF" \
		"sh <<EOF
release.sh merge
EOF" \
		"myrunner <<EOF
git push --force
EOF"
}

@test "heredoc: the fragment carrying the operator is scanned" {
	run_guard "$REPO" "git push --force <<EOF
release notes
EOF"

	assert_blocked
}

@test "heredoc: fragments after the terminator are scanned" {
	run_guard "$REPO" "git commit -F - <<'EOF'
release.sh merge lands the branch
EOF
git reset --hard"

	assert_blocked
}

@test "heredoc: an operator with no terminator line drops nothing" {
	run_guard "$REPO" "git commit -m 'see <<EOF for the shape'
git reset --hard"

	assert_blocked
}

@test "heredoc: a body piped from its reader into an interpreter is scanned" {
	run_guard "$REPO" "cat <<'EOF' | bash
git push --force origin main
EOF"

	assert_blocked
}

@test "heredoc: a body read inside a substitution an interpreter runs is scanned" {
	run_guard_heredoc <<'CMD'
bash -c "$(cat <<'EOF'
scripts/release.sh merge
EOF
)"
CMD

	assert_blocked
	assert_guard_output_includes "only through /release"
}

# ── Quoted option values (subcommand must stay visible) ──────────────────────

@test "quoted value: a banned subcommand behind a quoted -C or --git-dir value is blocked" {
	# shellcheck disable=SC2016
	each_blocked_in "$REPO" \
		'git -C "$wt" checkout .' \
		'for wt in .claude/worktrees/a .claude/worktrees/b; do echo "=== $wt ==="; git -C "$wt" checkout . 2>&1; done' \
		'git -C "$path" reset --hard' \
		'git --git-dir "$d" stash'
}

# ── Safe commands (never block) ──────────────────────────────────────────────

@test "safe: read-only and ordinary commands are allowed" {
	each_allowed_in "$REPO" \
		"git status" \
		"git log --oneline -10" \
		"git diff" \
		"git fetch origin" \
		"git pull" \
		"git merge main" \
		"git rebase main" \
		"git add ."
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
