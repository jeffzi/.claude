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

	export MERGE_MARKED_REPO
	MERGE_MARKED_REPO=$(setup_merge_marked_repo merge_marked_repo)

	export MERGE_STALE_REPO
	MERGE_STALE_REPO=$(setup_merge_marked_repo merge_stale_repo)
	backdate_merge_marker "$MERGE_STALE_REPO" "$STALE_OFFSET_MINUTES"
}

# Repo with a fresh merge-plan marker raised; prints the repo dir.
setup_merge_marked_repo() {
	local dir
	dir=$(setup_repo "$1")
	raise_merge_marker "$dir"
	printf '%s' "$dir"
}

teardown_file() {
	[[ -n "$TMPDIR_ROOT" ]] && rm -rf "$TMPDIR_ROOT"
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

@test "protect main: every commit-creating subcommand on main is blocked naming the protection and /merge-plan" {
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

		if ! assert_blocked || ! assert_guard_output_includes "protected" || ! assert_guard_output_includes "/merge-plan"; then
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

# ── merge-plan.sh (user-run) ─────────────────────────────────────────────────

@test "merge-plan: invoking the script without a marker is blocked as user-run" {
	# shellcheck disable=SC2088 # the literal tilde is the command under test, not a path this file expands
	run_guard "$REPO" "~/.claude/scripts/merge-plan.sh"

	assert_blocked
	assert_guard_output_includes "merge-plan.sh"
	assert_guard_output_includes "only through /merge-plan"
}

@test "merge-plan: every quoting and interpreter spelling of the invocation is blocked" {
	# shellcheck disable=SC2088
	each_blocked_in "$REPO" \
		"bash scripts/merge-plan.sh --skip-ci" \
		'bash "scripts/merge-plan.sh"' \
		'"~/.claude/scripts/merge-plan.sh" --skip-ci' \
		"/bin/bash scripts/merge-plan.sh" \
		"/usr/bin/env bash scripts/merge-plan.sh" \
		"command bash scripts/merge-plan.sh" \
		"exec scripts/merge-plan.sh" \
		"FOO=1 scripts/merge-plan.sh"
}

@test "merge-plan: the invocation is found behind every fragment boundary" {
	local heredoc
	heredoc=$(
		cat <<'CMD'
git commit -m "$(cat <<'EOF'
docs: describe how the plan branch lands
EOF
)" && "scripts/merge-plan.sh"
CMD
	)
	# shellcheck disable=SC2088
	each_blocked_in "$REPO" \
		'git commit -m "line one
line two" && bash ~/.claude/scripts/merge-plan.sh' \
		'cd /tmp
~/.claude/scripts/merge-plan.sh' \
		'git status
bash scripts/merge-plan.sh --skip-ci' \
		'echo a&"&b" ; bash scripts/merge-plan.sh' \
		'git status && "scripts/merge-plan.sh"' \
		"$heredoc"
}

@test "merge-plan: a message that merely names the script is allowed in every quoting" {
	each_allowed_in "$REPO" \
		'git commit -m "document merge-plan.sh"' \
		"git commit -m 'document merge-plan.sh'" \
		'git commit -m "notes
merge-plan.sh is user-run" && git status' \
		"git commit -m 'notes
merge-plan.sh is user-run' && git status"
}

@test "merge-plan: reading, linting, formatting, chmod, and bats on the script are allowed" {
	each_allowed_in "$REPO" \
		"cat scripts/merge-plan.sh" \
		"shellcheck -x scripts/merge-plan.sh" \
		"shfmt -d scripts/merge-plan.sh" \
		"chmod +x scripts/merge-plan.sh" \
		"bats tests/test_merge_plan.bats"
}

@test "merge-plan: every invocation spelling is allowed under a fresh marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$MERGE_MARKED_REPO" \
		"~/.claude/scripts/merge-plan.sh" \
		"bash scripts/merge-plan.sh --skip-ci" \
		'"~/.claude/scripts/merge-plan.sh" --skip-ci'
}

@test "merge-plan: invoking the script under a stale marker is blocked" {
	run_guard "$MERGE_STALE_REPO" "bash scripts/merge-plan.sh"

	assert_blocked
	assert_guard_output_includes "only through /merge-plan"
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
