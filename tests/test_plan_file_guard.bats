#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export STAGED_PLAN_REPO
	STAGED_PLAN_REPO=$(setup_repo staged_plan_repo)
	mkdir -p "$STAGED_PLAN_REPO/.claude/plans"
	printf 'plan content\n' >"$STAGED_PLAN_REPO/.claude/plans/phase.md"
	git -C "$STAGED_PLAN_REPO" add -f .claude/plans/phase.md

	export UNTRACKED_PLAN_REPO
	UNTRACKED_PLAN_REPO=$(setup_repo untracked_plan_repo)
	mkdir -p "$UNTRACKED_PLAN_REPO/.claude/plans"
	printf 'plan content\n' >"$UNTRACKED_PLAN_REPO/.claude/plans/phase.md"

	export MODIFIED_PLAN_REPO
	MODIFIED_PLAN_REPO=$(setup_repo modified_plan_repo)
	mkdir -p "$MODIFIED_PLAN_REPO/docs/plans"
	printf 'plan content\n' >"$MODIFIED_PLAN_REPO/docs/plans/phase.md"
	git -C "$MODIFIED_PLAN_REPO" add -f docs/plans/phase.md
	git -C "$MODIFIED_PLAN_REPO" -c commit.gpgsign=false commit -q -m "track plan"
	printf 'edited\n' >>"$MODIFIED_PLAN_REPO/docs/plans/phase.md"

	# A garbage index makes every read of staged or pending files fail while
	# the repository itself still resolves.
	export CORRUPT_INDEX_REPO
	CORRUPT_INDEX_REPO=$(setup_repo corrupt_index_repo)
	printf 'not an index\n' >"$(git -C "$CORRUPT_INDEX_REPO" rev-parse --absolute-git-dir)/index"

	# A linked worktree outside its main repository: the main repository holds
	# an untracked plan file, the clean worktree holds none, and the planned
	# worktree holds one while its main repository is clean.
	export LINKED_MAIN LINKED_CLEAN
	LINKED_MAIN=$(setup_repo linked_main)
	mkdir -p "$LINKED_MAIN/docs/plans"
	printf 'plan content\n' >"$LINKED_MAIN/docs/plans/phase.md"
	LINKED_CLEAN="$TMPDIR_ROOT/linked_clean"
	git -C "$LINKED_MAIN" worktree add -q -b clean "$LINKED_CLEAN"

	export LINKED_PLANNED
	LINKED_PLANNED="$TMPDIR_ROOT/linked_planned"
	git -C "$REPO" worktree add -q -b planned "$LINKED_PLANNED"
	mkdir -p "$LINKED_PLANNED/docs/plans"
	printf 'plan content\n' >"$LINKED_PLANNED/docs/plans/phase.md"

	# A git dir whose work tree is set by core.worktree, away from the git dir.
	export CORE_WORKTREE_TREE="$TMPDIR_ROOT/core_worktree_tree"
	git init -q --separate-git-dir "$TMPDIR_ROOT/core_worktree.git" "$CORE_WORKTREE_TREE"
	git --git-dir="$TMPDIR_ROOT/core_worktree.git" config core.worktree "$CORE_WORKTREE_TREE"

	export BARE_GIT_DIR="$TMPDIR_ROOT/bare.git"
	git init -q --bare "$BARE_GIT_DIR"

	export NO_REPO_DIR="$TMPDIR_ROOT/no_repo"
	mkdir -p "$NO_REPO_DIR/.claude/plans"
	printf 'plan content\n' >"$NO_REPO_DIR/.claude/plans/phase.md"
}

teardown_file() {
	cleanup_tmpdir_root
}

# Every command in the list is blocked from cwd $2 with output naming $1; a
# failure names the command.
each_blocked_for_in() {
	local reason="$1" dir="$2"
	shift 2
	for_each_case run_plan_guard "$dir" -- assert_blocked_with_reason "$reason" -- "$@"
}

# Every command in the list is allowed from cwd $1; a failure names the command.
each_allowed_in() {
	local dir="$1"
	shift
	for_each_case run_plan_guard "$dir" -- assert_allowed -- "$@"
}

# ── Add naming a plan path ───────────────────────────────────────────────────

@test "add plan: git add naming a .claude/plans/ path is blocked naming that pattern" {
	run_plan_guard "$REPO" "git add README .claude/plans/phase.md"

	assert_blocked_with_reason ".claude/plans/"
}

@test "add plan: git add naming a docs/plans/ path is blocked naming that pattern" {
	run_plan_guard "$REPO" "git add docs/plans/rollout.md"

	assert_blocked_with_reason "docs/plans/"
}

@test "add plan: git add naming only non-plan paths is allowed" {
	each_allowed_in "$REPO" \
		"git add README" \
		"git add docs/guide.md"
}

# ── Add of the whole tree ────────────────────────────────────────────────────

@test "add all: every whole-tree spelling is blocked when an untracked plan file is pending" {
	each_blocked_for_in ".claude/plans/" "$UNTRACKED_PLAN_REPO" \
		"git add ." \
		"git add -A" \
		"git add --all"
}

@test "add all: git add . is blocked when a tracked plan file is modified" {
	run_plan_guard "$MODIFIED_PLAN_REPO" "git add ."

	assert_blocked_with_reason "docs/plans/"
}

@test "add all: every whole-tree spelling is allowed when no plan file is pending" {
	each_allowed_in "$REPO" \
		"git add ." \
		"git add -A" \
		"git add --all"
}

# ── Add of tracked files ─────────────────────────────────────────────────────

@test "add update: every -u spelling is blocked when a tracked plan file is modified" {
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git add -u" \
		"git add --update"
}

@test "add update: git add -u is allowed when no tracked plan file is modified, even with one untracked" {
	each_allowed_in "$REPO" "git add -u" "git add --update"
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git add -u" "git add --update"
}

# ── Add of a directory ───────────────────────────────────────────────────────

@test "add dir: a directory holding .claude/plans/ is blocked when a plan file under it is untracked" {
	each_blocked_for_in ".claude/plans/" "$UNTRACKED_PLAN_REPO" \
		"git add .claude" \
		"git add .claude/" \
		"git add ./.claude" \
		"git add .claude/plans" \
		"git add ./.claude/plans/"
}

@test "add dir: a directory holding docs/plans/ is blocked when a plan file under it is modified" {
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git add docs" \
		"git add ./docs" \
		"git add ./docs/plans"
}

@test "add dir: a directory holding a plan directory is allowed when no plan file under it is pending" {
	each_allowed_in "$REPO" \
		"git add docs" \
		"git add .claude"
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git add docs"
}

@test "add dir: a pathspec that cannot hold a plan path is allowed beside pending plan files" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" \
		"git add src" \
		"git add README.md"
}

# ── Commit ───────────────────────────────────────────────────────────────────

@test "commit: git commit with a plan file staged is blocked naming its pattern" {
	run_plan_guard "$STAGED_PLAN_REPO" "git commit -m 'msg'"

	assert_blocked_with_reason ".claude/plans/"
}

@test "commit: git commit with no plan file staged is allowed, even with one untracked" {
	each_allowed_in "$REPO" "git commit -m 'msg'"
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git commit -m 'msg'"
}

@test "commit all: every -a spelling is blocked when a tracked plan file is modified" {
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git commit -a -m 'msg'" \
		"git commit --all -m 'msg'" \
		"git commit -am 'msg'" \
		"git commit -sam 'msg'"
}

@test "commit all: git commit -a is allowed when no tracked plan file is modified, even with one untracked" {
	each_allowed_in "$REPO" "git commit -a -m 'msg'"
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git commit -am 'msg'"
}

@test "commit all: a commit without -a keeps the staged-file rule beside a modified plan file" {
	each_allowed_in "$MODIFIED_PLAN_REPO" \
		"git commit -m 'msg'" \
		"git commit -ma" \
		"git commit -sm 'msg'" \
		"git commit --amend -m 'msg'"
}

# ── Targeted repository ──────────────────────────────────────────────────────

@test "named repo: add and commit aimed at a repo holding plan files read that repo from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" \
		"git -C $UNTRACKED_PLAN_REPO add ." \
		"cd $MODIFIED_PLAN_REPO && git add -A" \
		"git -C $STAGED_PLAN_REPO commit -m 'msg'" \
		"cd $STAGED_PLAN_REPO && git commit -m 'msg'" \
		"git --git-dir=$STAGED_PLAN_REPO/.git commit -m 'msg'" \
		"git --git-dir $STAGED_PLAN_REPO/.git commit -m 'msg'"
}

@test "named repo: add and commit aimed at a clean repo from a cwd holding plan files are allowed" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" \
		"git -C $REPO add ." \
		"cd $REPO && git add --all"
	each_allowed_in "$STAGED_PLAN_REPO" \
		"git -C $REPO commit -m 'msg'" \
		"git --git-dir=$REPO/.git commit -m 'msg'"
}

@test "named repo: add -u, add of a directory and commit -a read the repo they target from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" \
		"git -C $MODIFIED_PLAN_REPO add -u" \
		"git -C $UNTRACKED_PLAN_REPO add .claude" \
		"cd $MODIFIED_PLAN_REPO && git commit -am 'msg'"
}

@test "named repo: add -u, add of a directory and commit -a aimed at a clean repo from a planned cwd are allowed" {
	each_allowed_in "$MODIFIED_PLAN_REPO" \
		"git -C $REPO add -u" \
		"git -C $REPO add docs" \
		"git -C $REPO commit -am 'msg'"
}

@test "work tree: git add . in a linked worktree reads that worktree, not its main repository" {
	each_allowed_in "$LINKED_CLEAN" "git add ."

	run_plan_guard "$LINKED_PLANNED" "git add ."

	assert_blocked_with_reason "docs/plans/"
}

@test "work tree: git add . reads the work tree core.worktree names" {
	each_allowed_in "$CORE_WORKTREE_TREE" "git add ."

	mkdir -p "$CORE_WORKTREE_TREE/docs/plans"
	printf 'plan content\n' >"$CORE_WORKTREE_TREE/docs/plans/phase.md"
	run_plan_guard "$CORE_WORKTREE_TREE" "git add ."

	assert_blocked_with_reason "docs/plans/"
}

@test "work tree: git add . aimed at a bare repository is allowed" {
	each_allowed_in "$NO_REPO_DIR" "git --git-dir=$BARE_GIT_DIR add ."
}

# ── Commands the rules never read ────────────────────────────────────────────

@test "mention: a command that only mentions git add or git commit is allowed" {
	each_allowed_in "$STAGED_PLAN_REPO" \
		"echo git add docs/plans/x" \
		"rg 'git commit'"
}

@test "no repo: add and commit outside any repository are allowed" {
	each_allowed_in "$NO_REPO_DIR" \
		"git add .claude/plans/phase.md" \
		"git add ." \
		"git commit -m 'msg'"
}

@test "no repo: add and commit whose git dir is unknown are allowed" {
	# shellcheck disable=SC2016 # the literal expansions are the command text under test
	each_allowed_in "$STAGED_PLAN_REPO" \
		'git -C "$d" add .claude/plans/phase.md' \
		'git -C "$d" add .' \
		'git -C "$d" commit -m msg'
}

@test "unparseable: a command that does not parse is allowed" {
	run_plan_guard "$STAGED_PLAN_REPO" 'git commit -m "unterminated'

	assert_allowed
}

# ── Failures ─────────────────────────────────────────────────────────────────

@test "read failure: a failed read of pending files blocks git add . naming the repository" {
	run_plan_guard "$CORRUPT_INDEX_REPO" "git add ."

	assert_blocked_with_reason "corrupt_index_repo"
}

@test "read failure: a failed read of staged files blocks git commit naming the repository" {
	run_plan_guard "$CORRUPT_INDEX_REPO" "git commit -m 'msg'"

	assert_blocked_with_reason "corrupt_index_repo"
}

@test "helper failure: an ils parse failure blocks with its reason, even for a command with no git word" {
	local bin
	bin=$(failing_ils_bin "$TMPDIR_ROOT/broken_ils" 42)

	run_plan_guard "$REPO" "echo hi" "$bin:$PATH"

	assert_blocked_with_reason "42"
}

@test "helper failure: jq missing from PATH blocks naming jq" {
	run_plan_guard "$REPO" "echo hi" "$(path_without jq)"

	assert_blocked_with_reason "jq"
}
