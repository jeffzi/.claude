#!/usr/bin/env bats

# Every run points HOME into the test's temp dir and CLAUDE_CONFIG_DIR at a path
# under it, or empty, so the sweep never reaches the developer's real session data.

load helpers/hooks

readonly CLEANUP_SESSIONS_SCRIPT="$PROJECT_DIR/scripts/cleanup-sessions.sh"
readonly SESSION_ID="11111111-2222-3333-4444-555555555555"

setup() {
	HOME_DIR="$BATS_TEST_TMPDIR/home"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	HOME_SESSION=$(seed_stale_session "$HOME_DIR/.claude")
	CONFIG_SESSION=$(seed_stale_session "$CONFIG_DIR")
}

# Writes a session log under config dir $1, dated long past any sweep age, and
# prints its path.
seed_stale_session() {
	local project="$1/projects/-tmp-proj"
	mkdir -p "$project"
	printf 'log\n' >"$project/$SESSION_ID.jsonl"
	touch -t 202001010000 "$project/$SESSION_ID.jsonl"
	printf '%s' "$project/$SESSION_ID.jsonl"
}

# Runs `bash <script> 30 --execute` from $1 as script path $2, with
# CLAUDE_CONFIG_DIR set to $3; sets RUN_EXIT, RUN_STDOUT, RUN_STDERR.
run_sweep() {
	local dir="$1" script="$2" config="$3"
	run_capture "$dir" env "HOME=$HOME_DIR" "CLAUDE_CONFIG_DIR=$config" \
		"$BASH_BIN" "$script" 30 --execute
}

@test "CLAUDE_CONFIG_DIR set: deletes stale sessions under it and leaves ~/.claude alone" {
	run_sweep "$BATS_TEST_TMPDIR" "$CLEANUP_SESSIONS_SCRIPT" "$CONFIG_DIR"

	assert_run_ok
	[[ ! -e "$CONFIG_SESSION" ]]
	assert_present "$HOME_SESSION"
}

@test "CLAUDE_CONFIG_DIR empty: deletes stale sessions under ~/.claude" {
	run_sweep "$BATS_TEST_TMPDIR" "$CLEANUP_SESSIONS_SCRIPT" ""

	assert_run_ok
	[[ ! -e "$HOME_SESSION" ]]
	assert_present "$CONFIG_SESSION"
}

@test "CLAUDE_CONFIG_DIR missing: sweeps nothing and exits 0" {
	run_sweep "$BATS_TEST_TMPDIR" "$CLEANUP_SESSIONS_SCRIPT" "$BATS_TEST_TMPDIR/absent"

	assert_run_ok
	assert_present "$HOME_SESSION"
}

@test "run as a bare file name from scripts/: loads its helpers and sweeps" {
	run_sweep "$PROJECT_DIR/scripts" cleanup-sessions.sh "$CONFIG_DIR"

	assert_run_ok
	[[ ! -e "$CONFIG_SESSION" ]]
}
