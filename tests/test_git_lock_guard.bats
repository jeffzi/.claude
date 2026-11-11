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
	touch "$(index_lock_path "$LOCKED_REPO")"
}

teardown_file() {
	cleanup_tmpdir_root
}

# The lock path a block names, as the tail every spelling of the temp dir shares.
readonly LOCK_TAIL="locked_repo/.git/index.lock"

# Prints the path of the index lock of the repository at $1.
index_lock_path() {
	local git_dir
	git_dir=$(git -C "$1" rev-parse --absolute-git-dir) || return
	printf '%s/index.lock' "$git_dir"
}

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

@test "named repo: commit -C at an unlocked repo from a locked cwd proceeds at once" {
	run_lock_guard "$LOCKED_REPO" "git -C $REPO commit -m 'msg'"

	assert_allowed_without_lock
}

# ── Index-mutating invocations ───────────────────────────────────────────────

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
		"git commit -m 'msg'" \
		"git restore --staged README" \
		"git apply --index fix.patch" \
		"git apply -R3 fix.patch" \
		"git restore -S README" \
		"git restore -SW README" \
		"git restore -WS README"
}

@test "index writers: a locked repo's writer later in the command blocks after an unlocked one" {
	run_lock_guard "$REPO" "git -C $REPO add README && git -C $LOCKED_REPO commit -m 'msg'"

	assert_blocked_with_reason "$LOCK_TAIL"
}

# ── Lock outcome ─────────────────────────────────────────────────────────────

@test "timeout: a lock that persists blocks with its age in seconds" {
	local repo lock
	repo=$(setup_repo aged_repo)
	lock=$(index_lock_path "$repo")
	touch "$lock"
	backdate_seconds "$lock" 1000

	run_lock_guard "$repo" "git commit -m 'msg'"

	assert_blocked_with_reason "aged_repo/.git/index.lock"
	[[ "$GUARD_OUTPUT" =~ (^|[^0-9])100[0-5]([^0-9]|$) ]] || {
		printf 'no lock age near 1000 seconds in output: %s\n' "$GUARD_OUTPUT" >&2
		return 1
	}
}

@test "timeout: a lock that persists lists the holders the lsof on PATH reports" {
	local bin="$BATS_TEST_TMPDIR/holder/bin"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nprintf "COMMAND PID USER FD TYPE NAME\\nholder-proc 48213 tester 3w REG index.lock\\n"\n' >"$bin/lsof"
	chmod +x "$bin/lsof"

	run_lock_guard "$LOCKED_REPO" "git commit -m 'msg'" "$bin:$PATH"

	assert_blocked
	assert_guard_output_includes "48213"
}

@test "timeout: a lock that persists with no lsof on PATH says lsof is unavailable" {
	run_lock_guard "$LOCKED_REPO" "git commit -m 'msg'" "$(path_without lsof)"

	assert_blocked
	assert_guard_output_includes "unavailable"
	assert_guard_output_excludes "no lsof holders found"
}

@test "timeout: a lock that persists with lsof reporting nothing says no holders were found" {
	local bin
	bin=$(failing_program_bin "$BATS_TEST_TMPDIR" lsof 1)

	run_lock_guard "$LOCKED_REPO" "git commit -m 'msg'" "$bin:$PATH"

	assert_blocked
	assert_guard_output_includes "no lsof holders found"
}

@test "timeout: a lock that clears while the guard waits lets the writer proceed" {
	local repo lock bin="$BATS_TEST_TMPDIR/shim/bin" waited="$BATS_TEST_TMPDIR/sleep_called"
	repo=$(setup_repo clearing_repo)
	lock=$(index_lock_path "$repo")
	touch "$lock"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\ntouch %q\nrm -f %q\n' "$waited" "$lock" >"$bin/sleep"
	chmod +x "$bin/sleep"

	run_lock_guard "$repo" "git commit -m 'msg'" "$bin:$PATH"

	assert_allowed
	assert_present "$waited"
}

# ── Commands the guard never waits on ────────────────────────────────────────

@test "read-only: git commands that leave the index alone proceed at once despite the lock" {
	each_allowed_in "$LOCKED_REPO" \
		"git status" \
		"git restore -W README" \
		"git restore -sSTABLE README" \
		"git restore -- --staged" \
		"git apply fix.patch" \
		"git apply -p3 fix.patch" \
		"git apply -C3 fix.patch" \
		"git apply -- --index"
}

@test "no git: a command with no git invocation proceeds at once despite the lock" {
	each_allowed_in "$LOCKED_REPO" "echo git commit"
}
