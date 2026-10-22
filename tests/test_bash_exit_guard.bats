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

# The hook blocked the run: stdout is a block decision carrying the failure
# reason for exit code $1.
assert_blocked_for_exit() {
	[[ "$(jq -r '.decision' <<<"$RUN_STDOUT")" == "block" ]] || {
		printf 'expected "decision": "block" in stdout: %s\n' "$RUN_STDOUT" >&2
		return 1
	}
	assert_stdout_includes "COMMAND FAILED (exit code $1)"
}

# Run every "<code> <command>" case through the hook and apply assertion $1 to
# its exit code; a failure names the case.
each_case() {
	local assertion="$1" case code
	shift
	for case in "$@"; do
		code="${case%% *}"
		run_exit_guard "${case#* }" "$code"
		"$assertion" "$code" || {
			printf 'case: %s\n' "$case" >&2
			return 1
		}
	done
}

each_passes() {
	each_case assert_passed "$@"
}

# Every case is blocked with its exit code's reason.
each_blocked() {
	each_case assert_blocked_for_exit "$@"
}

# ── ils verdict codes ────────────────────────────────────────────────────────

@test "ils: a bare ils command exiting 4 (pending) or 5 (delivered, not green) passes" {
	each_passes \
		"4 ils push" \
		"5 ils push" \
		"4 ils"
}

@test "ils: a bare ils command exiting 1, 2, or 127 is blocked" {
	each_blocked \
		"1 ils push" \
		"2 ils push" \
		"127 ils push"
}

@test "ils: ils anywhere past the first word does not exempt exit 4 or 5" {
	each_blocked \
		"4 echo ils" \
		"5 cd x && ils push" \
		"4 ils-other" \
		"5 ils-other push"
}

# ── Other commands ───────────────────────────────────────────────────────────

@test "other commands: any non-zero exit is blocked, 4 and 5 included" {
	each_blocked \
		"1 make" \
		"4 make" \
		"5 make" \
		"2 ls missing" \
		"127 frobnicate"
}

@test "other commands: exit 0 passes" {
	run_exit_guard "make" 0

	assert_passed
}

@test "skip list: any non-zero exit from a probing command passes" {
	local code
	for code in 1 2 127; do
		each_passes \
			"$code grep foo file" \
			"$code rg foo" \
			"$code diff a b" \
			"$code test -f missing" \
			"$code which nope" \
			"$code false" \
			"$code true" \
			"$code command -v nope" \
			"$code [ -f missing ]"
	done
}

@test "tool: a non-Bash tool passes whatever its exit code" {
	run_exit_guard "make" 1 Read

	assert_passed
}
