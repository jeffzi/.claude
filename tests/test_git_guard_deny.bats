#!/usr/bin/env bats

load helpers/hooks
load helpers/guard

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

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
}

teardown_file() {
	cleanup_tmpdir_root
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
