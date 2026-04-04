#!/usr/bin/env bash
set -euo pipefail

HOOK="$HOME/.claude/hooks/git-guard.sh"
PASS=0
FAIL=0
SKIP=0

# ── Helpers ───────────────────────────────────────────────────────────────────

hook_input() {
	jq -n --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

# Run hook in a given directory, capture exit code and stderr
run_hook() {
	local dir="$1"
	local cmd="$2"
	local exit_code=0
	local stderr_out
	stderr_out=$(cd "$dir" && hook_input "$cmd" | bash "$HOOK" 2>&1 1>/dev/null) ||
		exit_code=$?
	printf '%d\t%s' "$exit_code" "$stderr_out"
}

expect_block() {
	local desc="$1"
	local dir="$2"
	local cmd="$3"
	local result exit_code
	result=$(run_hook "$dir" "$cmd")
	exit_code="${result%%	*}"
	if [[ "$exit_code" -eq 2 ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (exit %d, expected 2)\n" "$desc" "$exit_code"
		((++FAIL))
	fi
}

expect_allow() {
	local desc="$1"
	local dir="$2"
	local cmd="$3"
	local result exit_code
	result=$(run_hook "$dir" "$cmd")
	exit_code="${result%%	*}"
	if [[ "$exit_code" -eq 0 ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		local stderr="${result#*	}"
		printf "FAIL  %s  (exit %d, expected 0)\n    stderr: %s\n" "$desc" "$exit_code" "$stderr"
		((++FAIL))
	fi
}

# ── Fixtures ──────────────────────────────────────────────────────────────────

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

setup_repo() {
	local dir="$TMPDIR_ROOT/$1"
	mkdir -p "$dir"
	git -C "$dir" init -q
	git -C "$dir" config user.email "test@test.com"
	git -C "$dir" config user.name "Test"
	# Initial commit so HEAD exists
	touch "$dir/README"
	git -C "$dir" add README
	git -C "$dir" -c commit.gpgsign=false commit -q -m "init"
	printf '%s' "$dir"
}

REPO=$(setup_repo repo)

# Repo with staged plan files (force-add to bypass global gitignore in test setup only)
PLAN_REPO=$(setup_repo plan_repo)
mkdir -p "$PLAN_REPO/.claude/plans"
printf 'plan content\n' >"$PLAN_REPO/.claude/plans/phase.md"
git -C "$PLAN_REPO" add -f .claude/plans/phase.md

# ── Tests ─────────────────────────────────────────────────────────────────────

printf "\n── Push ─────────────────────────────────────────────────────────────────────\n"
expect_block "git push origin main" "$REPO" "git push origin main"
expect_block "git push --force" "$REPO" "git push --force"
expect_block "git push -u origin HEAD" "$REPO" "git push -u origin HEAD"

printf "\n── Checkout (discard) ───────────────────────────────────────────────────────\n"
expect_block "git checkout -- file" "$REPO" "git checkout -- file"
expect_block "git checkout HEAD -- file" "$REPO" "git checkout HEAD -- file"
expect_block "git checkout ." "$REPO" "git checkout ."
expect_block "git checkout -f branch" "$REPO" "git checkout -f branch"
expect_block "git checkout --force branch" "$REPO" "git checkout --force branch"
expect_allow "git checkout branch" "$REPO" "git checkout branch"
expect_allow "git checkout -b new-branch" "$REPO" "git checkout -b new-branch"
expect_allow "git checkout -b feat/my.feature" "$REPO" "git checkout -b feat/my.feature"

printf "\n── Switch (discard) ─────────────────────────────────────────────────────────\n"
expect_block "git switch -f branch" "$REPO" "git switch -f branch"
expect_block "git switch --force branch" "$REPO" "git switch --force branch"
expect_block "git switch --discard-changes b" "$REPO" "git switch --discard-changes branch"
expect_allow "git switch branch" "$REPO" "git switch branch"
expect_allow "git switch -c new-branch" "$REPO" "git switch -c new-branch"

printf "\n── Reset ────────────────────────────────────────────────────────────────────\n"
expect_block "git reset" "$REPO" "git reset"
expect_block "git reset HEAD" "$REPO" "git reset HEAD"
expect_block "git reset --soft HEAD~1" "$REPO" "git reset --soft HEAD~1"
expect_block "git reset --hard" "$REPO" "git reset --hard"

printf "\n── Clean ────────────────────────────────────────────────────────────────────\n"
expect_block "git clean -f" "$REPO" "git clean -f"
expect_block "git clean -fd" "$REPO" "git clean -fd"
expect_block "git clean -fdx" "$REPO" "git clean -fdx"
expect_allow "git clean -n" "$REPO" "git clean -n"
expect_allow "git clean --dry-run" "$REPO" "git clean --dry-run"

printf "\n── Stash ────────────────────────────────────────────────────────────────────\n"
expect_block "git stash" "$REPO" "git stash"
expect_block "git stash push" "$REPO" "git stash push"
expect_block "git stash list" "$REPO" "git stash list"
expect_block "git stash pop" "$REPO" "git stash pop"

printf "\n── Branch ───────────────────────────────────────────────────────────────────\n"
expect_block "git branch -D feature" "$REPO" "git branch -D feature"
expect_allow "git branch -d feature" "$REPO" "git branch -d feature"
expect_allow "git branch -a" "$REPO" "git branch -a"
expect_allow "git branch new-branch" "$REPO" "git branch new-branch"

printf "\n── Restore ──────────────────────────────────────────────────────────────────\n"
expect_block "git restore file" "$REPO" "git restore file"
expect_block "git restore ." "$REPO" "git restore ."
expect_allow "git restore --staged file" "$REPO" "git restore --staged file"
expect_allow "git restore --staged ." "$REPO" "git restore --staged ."

printf "\n── Commit ───────────────────────────────────────────────────────────────────\n"
expect_block "git commit --amend" "$REPO" "git commit --amend"
expect_block "git commit --amend --no-edit" "$REPO" "git commit --amend --no-edit"
expect_allow "git commit -m 'msg'" "$REPO" "git commit -m 'msg'"
expect_block "git commit (plan files staged)" "$PLAN_REPO" "git commit -m 'msg'"

printf "\n── --no-verify (any subcommand) ─────────────────────────────────────────────\n"
expect_block "git commit --no-verify" "$REPO" "git commit --no-verify -m 'msg'"
expect_block "git push --no-verify" "$REPO" "git push --no-verify"

printf "\n── History extraction with redirect ─────────────────────────────────────────\n"
expect_block "git show > file" "$REPO" "git show HEAD > output.txt"
expect_block "git cat-file > file" "$REPO" "git cat-file blob HEAD:README > out"
expect_allow "git show 2>file (stderr only)" "$REPO" "git show HEAD 2>errors.txt"

printf "\n── Apply reverse ────────────────────────────────────────────────────────────\n"
expect_block "git apply -R" "$REPO" "git apply -R patch.diff"
expect_block "git apply --reverse" "$REPO" "git apply --reverse patch.diff"
expect_allow "git apply patch" "$REPO" "git apply patch.diff"

printf "\n── Add (plan file protection) ───────────────────────────────────────────────\n"
expect_block "git add explicit plan file" "$PLAN_REPO" "git add .claude/plans/phase.md"
expect_allow "git add normal file" "$REPO" "git add README"

printf "\n── Chained commands ─────────────────────────────────────────────────────────\n"
expect_block "add then checkout discard" "$REPO" "git add . && git checkout -- ."
expect_block "push in chain" "$REPO" "git status && git push origin main"
expect_block "stash in chain with semicolon" "$REPO" "git status; git stash"

printf "\n── Safe commands (never block) ──────────────────────────────────────────────\n"
expect_allow "git status" "$REPO" "git status"
expect_allow "git log" "$REPO" "git log --oneline -10"
expect_allow "git diff" "$REPO" "git diff"
expect_allow "git fetch" "$REPO" "git fetch origin"
expect_allow "git pull" "$REPO" "git pull"
expect_allow "git merge" "$REPO" "git merge main"
expect_allow "git add ." "$REPO" "git add ."

printf "\n─────────────────────────────────────────────────────────────────────────────\n"
printf "%d passed, %d failed" "$PASS" "$FAIL"
[[ "$SKIP" -gt 0 ]] && printf ", %d skipped" "$SKIP"
printf "\n"
[[ "$FAIL" -eq 0 ]]
