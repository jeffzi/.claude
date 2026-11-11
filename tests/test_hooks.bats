#!/usr/bin/env bats

load helpers/hooks

# Runs hook $1 from inside hooks/ on a plain command, once by full path and once
# as `bash $1.sh`; keeps the full-path run in FULL_* and the bare one in RUN_*.
run_hook_both_ways() {
	local input
	input=$(bash_hook_input "echo hi" "$BATS_TEST_TMPDIR")
	run_capture "$PROJECT_DIR/hooks" "$BASH_BIN" "$PROJECT_DIR/hooks/$1.sh" <<<"$input"
	FULL_EXIT=$RUN_EXIT FULL_STDOUT=$RUN_STDOUT FULL_STDERR=$RUN_STDERR
	run_hook_by_bare_name "$1.sh" "$input"
}

# The bare-name run matched the full-path one: same exit, stdout and stderr.
assert_bare_matches_full() {
	[[ "$RUN_EXIT" == "$FULL_EXIT" && "$RUN_STDOUT" == "$FULL_STDOUT" &&
		"$RUN_STDERR" == "$FULL_STDERR" ]] || {
		printf 'bare name exit %s (full path %s)\nstderr: %s\n' "$RUN_EXIT" "$FULL_EXIT" "$RUN_STDERR" >&2
		return 1
	}
}

@test "bare name: every hook run as bash <hook>.sh from inside hooks/ behaves as by full path" {
	for_each_case run_hook_both_ways -- assert_bare_matches_full -- \
		bash-exit-guard git-commit-guard git-lock-guard plan-file-guard \
		tdd-cycle-guard tdd-red-guard worktree-guard
}
