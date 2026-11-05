#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export GIT_LOCK_GUARD_TIMEOUT_MS=200

	export REPO
	REPO=$(setup_repo repo)

	export LOCKED_REPO
	LOCKED_REPO=$(setup_repo locked_repo)
	touch "$(git -C "$LOCKED_REPO" rev-parse --absolute-git-dir)/index.lock"

	export NO_REPO_DIR="$TMPDIR_ROOT/no_repo"
	mkdir -p "$NO_REPO_DIR"
}

teardown_file() {
	cleanup_tmpdir_root
}

@test "named repo: commit -C at a locked repo from an unlocked cwd waits and names that repo's lock" {
	run_lock_guard "$REPO" "git -C $LOCKED_REPO commit -m 'msg'"

	assert_blocked
	assert_guard_output_includes "locked_repo/.git/index.lock"
}

@test "named repo: commit -C at a locked repo from outside any repo waits and names that repo's lock" {
	run_lock_guard "$NO_REPO_DIR" "git -C $LOCKED_REPO commit -m 'msg'"

	assert_blocked
	assert_guard_output_includes "locked_repo/.git/index.lock"
}

@test "named repo: commit -C at an unlocked repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git -C $REPO commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

@test "named repo: commit -C at a path that is no repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git -C $TMPDIR_ROOT/absent commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

@test "named repo: commit --git-dir at a path that is no repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git --git-dir=$TMPDIR_ROOT/absent/.git commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

@test "named repo: commit with a separate --git-dir word at a path that is no repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git --git-dir $TMPDIR_ROOT/absent/.git commit -m 'msg'"

	assert_allowed
	assert_guard_output_excludes "index.lock"
}

# ── Index-mutating invocations ───────────────────────────────────────────────

# The lock path a block names, as the tail every spelling of the temp dir shares.
readonly LOCK_TAIL="locked_repo/.git/index.lock"

# Every command in the list is blocked from cwd $1 with output naming the
# locked repo's lock; a failure names the command.
each_blocked_in() {
	local dir="$1"
	shift
	for_each_case run_lock_guard "$dir" -- assert_blocked_with_reason "$LOCK_TAIL" -- "$@"
}

# Every command in the list is allowed from cwd $1 without naming any lock; a
# failure names the command.
each_allowed_in() {
	local dir="$1"
	shift
	for_each_case run_lock_guard "$dir" -- assert_allowed_without_lock -- "$@"
}

assert_allowed_without_lock() {
	assert_allowed && assert_guard_output_excludes "index.lock"
}

# Sets the mtime of $1 to $2 seconds before now, to the second.
backdate_seconds() {
	local path="$1" seconds="$2" epoch stamp
	epoch=$(($(date +%s) - seconds))
	if stamp=$(date -r "$epoch" +%Y%m%d%H%M.%S 2>/dev/null); then
		touch -t "$stamp" "$path"
	else
		touch -d "@$epoch" "$path"
	fi
}

@test "index writers: every index-mutating subcommand waits on the cwd repo's lock and blocks naming it" {
	each_blocked_in "$LOCKED_REPO" \
		"git add README" \
		"git commit -m 'msg'" \
		"git rm README" \
		"git mv README README2" \
		"git merge main" \
		"git cherry-pick HEAD" \
		"git revert HEAD" \
		"git am fix.patch" \
		"git pull" \
		"git update-index --refresh" \
		"git commit-tree HEAD^{tree} -m 'msg'" \
		"git restore --staged README" \
		"git restore -S README" \
		"git restore -SW README" \
		"git restore -WS README"
}

@test "index writers: an index writer after cd or a leading command waits on its repo's lock" {
	each_blocked_in "$REPO" \
		"cd $LOCKED_REPO && git add README" \
		"true && git -C $LOCKED_REPO add README" \
		"echo start; git -C $LOCKED_REPO commit -m 'msg'"
}

@test "index writers: a locked repo's writer later in the command blocks after an unlocked one" {
	run_lock_guard "$REPO" "git -C $REPO add README && git -C $LOCKED_REPO commit -m 'msg'"

	assert_blocked_with_reason "$LOCK_TAIL"
}

# ── Lock outcome ─────────────────────────────────────────────────────────────

@test "timeout: a lock that persists blocks with its age in seconds" {
	local repo lock
	repo=$(setup_repo aged_repo)
	lock="$(git -C "$repo" rev-parse --absolute-git-dir)/index.lock"
	touch "$lock"
	backdate_seconds "$lock" 1000

	run_lock_guard "$repo" "git commit -m 'msg'"

	assert_blocked_with_reason "aged_repo/.git/index.lock"
	[[ "$GUARD_OUTPUT" =~ (^|[^0-9])100[0-5]([^0-9]|$) ]] || {
		printf 'no lock age near 1000 seconds in output: %s\n' "$GUARD_OUTPUT" >&2
		return 1
	}
}

@test "timeout: a lock that clears before the timeout lets the writer proceed" {
	local repo lock
	repo=$(setup_repo clearing_repo)
	lock="$(git -C "$repo" rev-parse --absolute-git-dir)/index.lock"
	touch "$lock"
	(sleep 0.3 && rm -f "$lock") >/dev/null 2>&1 3>&- &

	GIT_LOCK_GUARD_TIMEOUT_MS=10000 run_lock_guard "$repo" "git commit -m 'msg'"

	assert_allowed
}

@test "no lock: an index writer in an unlocked repo proceeds at once" {
	each_allowed_in "$REPO" "git add README"
}

# ── Commands the guard never waits on ────────────────────────────────────────

@test "read-only: git commands that leave the index alone proceed at once despite the lock" {
	each_allowed_in "$LOCKED_REPO" \
		"git status" \
		"git diff --cached" \
		"git log --oneline" \
		"git restore README" \
		"git restore -W README" \
		"git restore -sSTABLE README" \
		"git restore -- --staged"
}

@test "no git: a command with no git invocation proceeds at once despite the lock" {
	each_allowed_in "$LOCKED_REPO" \
		"echo git commit" \
		"ls"
}

@test "no repo: an index writer outside any repository proceeds at once" {
	each_allowed_in "$NO_REPO_DIR" "git commit -m 'msg'"
}

# ── Helper failures ──────────────────────────────────────────────────────────

@test "helper failure: an ils parse failure blocks with its reason" {
	local bin
	bin=$(failing_ils_bin "$TMPDIR_ROOT/broken_ils" 42)

	run_lock_guard "$REPO" "git commit -m 'msg'" "$bin:$PATH"

	assert_blocked_with_reason "42"
}

@test "helper failure: jq missing from PATH blocks naming jq" {
	run_lock_guard "$REPO" "git commit -m 'msg'" "$(path_without jq)"

	assert_blocked_with_reason "jq"
}
