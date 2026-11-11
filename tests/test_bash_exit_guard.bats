#!/usr/bin/env bats

load helpers/hooks

# Each case below is "<exit code> <command>": the code the Bash tool reported
# for the command, then the command text itself.

# The hook let the run through: exit 0 and nothing on stdout or stderr, so no
# block JSON and nothing else for the model to read.
assert_passed() {
	((RUN_EXIT == 0)) && [[ -z "$RUN_STDOUT" && -z "$RUN_STDERR" ]] || {
		printf 'expected exit 0 with empty stdout and stderr\nexit: %d\nstdout: %s\nstderr: %s\n' \
			"$RUN_EXIT" "$RUN_STDOUT" "$RUN_STDERR" >&2
		return 1
	}
}

# The hook blocked the run of case $1: stdout is a block decision carrying the
# failure reason for the case's exit code.
assert_blocked_for_exit() {
	[[ "$(jq -r '.decision' <<<"$RUN_STDOUT")" == "block" ]] || {
		printf 'expected "decision": "block" in stdout: %s\n' "$RUN_STDOUT" >&2
		return 1
	}
	assert_stdout_includes "COMMAND FAILED (exit code ${1%% *})"
}

# Run the hook on case $1, a "<code> <command>" string.
run_exit_case() {
	run_exit_guard "${1#* }" "${1%% *}"
}

each_passes() {
	for_each_case run_exit_case -- assert_passed -- "$@"
}

each_blocked() {
	for_each_case run_exit_case -- assert_blocked_for_exit -- "$@"
}

# ── ils verdict codes ────────────────────────────────────────────────────────

@test "ils: a bare ils command exiting 4 (pending) or 5 (delivered, not green) passes" {
	each_passes \
		"4 ils push" \
		"5 ils push"
}

@test "ils: a bare ils command exiting 1, 2, or 127 is blocked" {
	each_blocked \
		"1 ils push"
}

@test "ils: ils anywhere past the first word does not exempt exit 4 or 5" {
	each_blocked \
		"4 echo ils" \
		"4 ils-other"
}

# ── Other commands ───────────────────────────────────────────────────────────

@test "other commands: any non-zero exit is blocked" {
	each_blocked \
		"1 make"
}

@test "other commands: exit 0 passes" {
	run_exit_guard "make" 0

	assert_passed
}

@test "skip list: any non-zero exit from a probing command passes" {
	each_passes \
		"1 grep foo file" \
		"2 command -v nope" \
		"127 [ -f missing ]"
}

@test "skip list: a probing command followed by a tab, after a space or behind an assignment passes" {
	each_passes \
		$'1 grep\tfoo file' \
		"1  grep foo file" \
		"1 FOO=1 grep foo file"
}

@test "skip list: a probing command chained with another command is blocked" {
	each_blocked \
		"1 test -d . && npm run build" \
		"1 grep -q x f; make" \
		"1 [ -f x ] || cargo build" \
		"1 make; grep -q x f" \
		"1 command make"
}

@test "unparsable: a failed command ils cannot parse passes when its first word is on the skip list" {
	each_passes "1 grep 'unterminated" "2 command -v 'unterminated"
}

@test "unparsable: a failed command ils cannot parse is blocked when its first word is off the skip list" {
	each_blocked "1 make 'unterminated"
}

@test "tool: a non-Bash tool passes whatever its exit code" {
	run_exit_guard "make" 1 Read

	assert_passed
}

# ── Dependencies ─────────────────────────────────────────────────────────────

@test "dependencies: without jq on PATH the hook exits 2 naming jq" {
	local input="$BATS_TEST_TMPDIR/input.json"
	exit_hook_input "make" 1 >"$input"

	run_script_on_path "$BATS_TEST_TMPDIR" "$(path_without jq)" \
		"$BASH_BIN" "$BASH_EXIT_GUARD_HOOK" <"$input"

	assert_run_failed 2
	assert_reason_names_program jq
}

# The hook refused the run instead of letting it through: a block decision on
# stdout, or exit 2 with a reason on stderr.
assert_refused() {
	[[ "$(jq -r '.decision' <<<"$RUN_STDOUT" 2>/dev/null)" == "block" ]] && return 0
	((RUN_EXIT == 2)) && [[ -n "$RUN_STDERR" ]] || {
		printf 'expected a block decision or exit 2 with stderr\nexit: %d\nstdout: %s\nstderr: %s\n' \
			"$RUN_EXIT" "$RUN_STDOUT" "$RUN_STDERR" >&2
		return 1
	}
}

# Run the hook on a failed `grep foo file` with PATH $1 for the hook alone.
run_failed_grep_on_path() {
	local input="$BATS_TEST_TMPDIR/input.json"
	exit_hook_input "grep foo file" 1 >"$input"

	run_script_on_path "$BATS_TEST_TMPDIR" "$1" "$BASH_BIN" "$BASH_EXIT_GUARD_HOOK" <"$input"
}

@test "dependencies: without ils on PATH a failed probing command is refused" {
	run_failed_grep_on_path "$(path_without ils)"

	assert_refused
}

@test "dependencies: ils parse exiting with neither 0 nor 1 refuses a failed probing command" {
	local bin
	bin=$(failing_ils_bin "$BATS_TEST_TMPDIR/broken_ils" 42)

	run_failed_grep_on_path "$bin:$PATH"

	assert_refused
}
