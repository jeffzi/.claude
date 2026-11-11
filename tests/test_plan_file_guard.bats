#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export STAGED_PLAN_REPO
	STAGED_PLAN_REPO=$(setup_repo staged_plan_repo)
	write_plan_file "$STAGED_PLAN_REPO" .claude/plans
	git -C "$STAGED_PLAN_REPO" add -f .claude/plans/phase.md

	export UNTRACKED_PLAN_REPO
	UNTRACKED_PLAN_REPO=$(setup_repo untracked_plan_repo)
	write_plan_file "$UNTRACKED_PLAN_REPO" .claude/plans

	export MODIFIED_PLAN_REPO
	MODIFIED_PLAN_REPO=$(setup_repo modified_plan_repo)
	write_plan_file "$MODIFIED_PLAN_REPO" docs/plans
	git -C "$MODIFIED_PLAN_REPO" add -f docs/plans/phase.md
	git -C "$MODIFIED_PLAN_REPO" -c commit.gpgsign=false commit -q -m "track plan"
	printf 'edited\n' >>"$MODIFIED_PLAN_REPO/docs/plans/phase.md"

	# A plan file git ignores: only a forced add stages it.
	export IGNORED_PLAN_REPO
	IGNORED_PLAN_REPO=$(setup_repo ignored_plan_repo)
	printf 'docs/plans/\n' >"$IGNORED_PLAN_REPO/.gitignore"
	git -C "$IGNORED_PLAN_REPO" add .gitignore
	git -C "$IGNORED_PLAN_REPO" -c commit.gpgsign=false commit -q -m "ignore plans"
	write_plan_file "$IGNORED_PLAN_REPO" docs/plans

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
	write_plan_file "$LINKED_MAIN" docs/plans
	LINKED_CLEAN="$TMPDIR_ROOT/linked_clean"
	git -C "$LINKED_MAIN" worktree add -q -b clean "$LINKED_CLEAN"

	export LINKED_PLANNED
	LINKED_PLANNED="$TMPDIR_ROOT/linked_planned"
	git -C "$REPO" worktree add -q -b planned "$LINKED_PLANNED"
	write_plan_file "$LINKED_PLANNED" docs/plans

	# A git dir whose work tree is set by core.worktree, away from the git dir:
	# one work tree holds no plan file, the other holds one.
	export CORE_WORKTREE_TREE="$TMPDIR_ROOT/core_worktree_tree"
	git init -q --separate-git-dir "$TMPDIR_ROOT/core_worktree.git" "$CORE_WORKTREE_TREE"
	git --git-dir="$TMPDIR_ROOT/core_worktree.git" config core.worktree "$CORE_WORKTREE_TREE"

	export CORE_WORKTREE_PLANNED_TREE="$TMPDIR_ROOT/core_worktree_planned_tree"
	git init -q --separate-git-dir "$TMPDIR_ROOT/core_worktree_planned.git" "$CORE_WORKTREE_PLANNED_TREE"
	git --git-dir="$TMPDIR_ROOT/core_worktree_planned.git" config core.worktree "$CORE_WORKTREE_PLANNED_TREE"
	write_plan_file "$CORE_WORKTREE_PLANNED_TREE" docs/plans

	export BARE_GIT_DIR="$TMPDIR_ROOT/bare.git"
	git init -q --bare "$BARE_GIT_DIR"

	export NO_REPO_DIR="$TMPDIR_ROOT/no_repo"
	write_plan_file "$NO_REPO_DIR" .claude/plans
}

teardown_file() {
	cleanup_tmpdir_root
}

# Writes a plan file under directory $2 of $1.
write_plan_file() {
	mkdir -p "$1/$2"
	printf 'plan content\n' >"$1/$2/phase.md"
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

@test "add plan: git add naming only non-plan paths is allowed" {
	each_allowed_in "$REPO" "git add docs/guide.md"
}

# ── Add of the whole tree ────────────────────────────────────────────────────

@test "add all: every whole-tree spelling is blocked when an untracked plan file is pending" {
	each_blocked_for_in ".claude/plans/" "$UNTRACKED_PLAN_REPO" \
		"git add -A" \
		"git add --all"
}

@test "add all: git add . is blocked when a tracked plan file is modified" {
	run_plan_guard "$MODIFIED_PLAN_REPO" "git add ."

	assert_blocked_with_reason "docs/plans/"
}

@test "add all: git add . is allowed when no plan file is pending" {
	each_allowed_in "$REPO" "git add ."
}

# ── Add of tracked files ─────────────────────────────────────────────────────

@test "add options: a word after -- is a pathspec, never an option" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git add -- -A"
}

@test "add update: every -u spelling is blocked when a tracked plan file is modified" {
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git add -u" \
		"git add --update"
}

@test "add update: every -u spelling is allowed when the only plan file is untracked" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git add -u" "git add --update"
}

# ── Add of a directory ───────────────────────────────────────────────────────

@test "add dir: a directory holding .claude/plans/ is blocked when a plan file under it is untracked" {
	each_blocked_for_in ".claude/plans/" "$UNTRACKED_PLAN_REPO" \
		"git add .claude"
}

@test "add dir: a directory holding docs/plans/ is blocked when a plan file under it is modified" {
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git add docs"
}

@test "add dir: a directory holding no pending plan file is allowed beside a pending one elsewhere" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git add docs"
}

# ── Add with force ───────────────────────────────────────────────────────────

@test "add force: every forced spelling reaching an ignored plan file is blocked naming its pattern" {
	each_blocked_for_in "docs/plans/" "$IGNORED_PLAN_REPO" \
		"git add -f docs" \
		"git add --force docs" \
		"git add -vf docs" \
		"git add -fA" \
		"git add -f ." \
		"git add -f docs/plans"
}

@test "add force: an add without force is allowed when the only plan file is ignored" {
	each_allowed_in "$IGNORED_PLAN_REPO" \
		"git add docs" \
		"git add -A"
}

# ── Commit ───────────────────────────────────────────────────────────────────

@test "commit: git commit with a plan file staged is blocked naming its pattern" {
	run_plan_guard "$STAGED_PLAN_REPO" "git commit -m 'msg'"

	assert_blocked_with_reason ".claude/plans/"
}

@test "commit: git commit is allowed when the only plan file is untracked" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git commit -m 'msg'"
}

@test "commit all: every -a spelling is blocked when a tracked plan file is modified" {
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git commit --all -m 'msg'" \
		"git commit -am 'msg'" \
		"git commit -sam 'msg'"
}

@test "commit all: git commit -a is allowed when the only plan file is untracked" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git commit -am 'msg'"
}

@test "commit all: a commit without -a keeps the staged-file rule beside a modified plan file" {
	each_allowed_in "$MODIFIED_PLAN_REPO" \
		"git commit -m 'msg'" \
		"git commit -ma" \
		"git commit --amend -m 'msg'"
}

# ── Targeted repository ──────────────────────────────────────────────────────

@test "commit pathspec: a pathspec matching a modified plan file is blocked" {
	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	each_blocked_for_in "docs/plans/" "$MODIFIED_PLAN_REPO" \
		"git commit -m 'msg' docs" \
		"git commit -m 'msg' -- docs" \
		'git commit -m "$(date)" docs'
}

@test "commit pathspec: an option value or a pathspec matching no plan file is allowed" {
	each_allowed_in "$MODIFIED_PLAN_REPO" \
		"git commit -m docs" \
		"git commit --message docs" \
		"git commit -mdocs" \
		"git commit -m 'msg' README"
}

@test "named repo: git add aimed at a repo holding plan files reads that repo from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" "git -C $UNTRACKED_PLAN_REPO add ."
}

@test "named repo: git commit aimed at a repo holding a staged plan file reads that repo from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" "git -C $STAGED_PLAN_REPO commit -m 'msg'"
}

@test "named repo: git add aimed at a clean repo from a cwd holding plan files is allowed" {
	each_allowed_in "$UNTRACKED_PLAN_REPO" "git -C $REPO add ."
}

@test "named repo: git commit aimed at a clean repo from a cwd holding a staged plan file is allowed" {
	each_allowed_in "$STAGED_PLAN_REPO" "git -C $REPO commit -m 'msg'"
}

@test "named repo: add -u aimed at a repo holding a modified plan file reads that repo from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" "git -C $MODIFIED_PLAN_REPO add -u"
}

@test "named repo: add of a directory aimed at a repo holding an untracked plan file reads that repo from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" "git -C $UNTRACKED_PLAN_REPO add .claude"
}

@test "named repo: commit -a aimed at a repo holding a modified plan file reads that repo from a clean cwd" {
	each_blocked_for_in "plans/" "$REPO" "cd $MODIFIED_PLAN_REPO && git commit -am 'msg'"
}

@test "named repo: add -u or add of a directory aimed at a clean repo from a planned cwd is allowed" {
	each_allowed_in "$MODIFIED_PLAN_REPO" \
		"git -C $REPO add -u" \
		"git -C $REPO add docs"
}

@test "named repo: commit -a aimed at a clean repo from a planned cwd is allowed" {
	each_allowed_in "$MODIFIED_PLAN_REPO" "git -C $REPO commit -am 'msg'"
}

@test "work tree: git add . in a linked worktree with no plan file is allowed although its main repository holds one" {
	each_allowed_in "$LINKED_CLEAN" "git add ."
}

@test "work tree: git add . in a linked worktree holding a plan file is blocked" {
	run_plan_guard "$LINKED_PLANNED" "git add ."

	assert_blocked_with_reason "docs/plans/"
}

@test "work tree: git add . is allowed when the work tree core.worktree names holds no plan file" {
	each_allowed_in "$CORE_WORKTREE_TREE" "git add ."
}

@test "work tree: git add . is blocked when the work tree core.worktree names holds a plan file" {
	run_plan_guard "$CORE_WORKTREE_PLANNED_TREE" "git add ."

	assert_blocked_with_reason "docs/plans/"
}

@test "work tree: git add . aimed at a bare repository is allowed" {
	each_allowed_in "$NO_REPO_DIR" "git --git-dir=$BARE_GIT_DIR add ."
}

# ── Commands the rules never read ────────────────────────────────────────────

@test "mention: a command that only mentions git add or git commit is allowed" {
	each_allowed_in "$STAGED_PLAN_REPO" "echo git add docs/plans/x"
}

@test "no repo: git add outside any repository is allowed" {
	each_allowed_in "$NO_REPO_DIR" "git add .claude/plans/phase.md"
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

@test "unexpected failure: a failing mktemp exits 2 naming the hook and the failed status" {
	local bin
	bin=$(failing_program_bin "$TMPDIR_ROOT/broken_mktemp" mktemp 42)

	run_plan_guard "$REPO" "git add docs/plans/x.md" "$bin:$PATH"

	assert_blocked_with_reason "plan-file-guard"
	assert_guard_output_includes "42"
}

# Run plan-file-guard from $1 on command $2 under bash binary $3.
run_plan_guard_under() {
	run_plan_guard "$1" "$2" "" "$3"
}

@test "unparsable: a command ils cannot parse is allowed under bash 3.2 and the current bash" {
	for_each_case run_plan_guard_under "$REPO" 'git add docs/plans/x.md "unterminated' -- \
		assert_allowed -- /bin/bash "$BASH_BIN"
}
