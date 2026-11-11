#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)
	mkdir -p "$REPO/src" "$REPO/tests"
	printf 'def foo() -> int:\n    return 1\n' >"$REPO/src/mod.py"
	printf 'def bar() -> int:\n    return 2\n' >"$REPO/src/my file.py"
	printf 'def test_foo() -> None:\n    assert foo() == 1\n' >"$REPO/tests/test_mod.py"

	export MARKER
	MARKER=$(tdd_marker_path "$REPO")

	# A repository checked out under a directory named like a test directory.
	export SPEC_REPO
	SPEC_REPO=$(setup_repo spec/proj)
	mkdir -p "$SPEC_REPO/src"
	printf 'def foo() -> int:\n    return 1\n' >"$SPEC_REPO/src/mod.py"
}

teardown_file() {
	cleanup_tmpdir_root
}

# Run tdd-red-guard in $1 on PATH $2 for the hook alone, fed the payload that
# builder $3.. prints on the current PATH; sets GUARD_EXIT and GUARD_OUTPUT.
run_tdd_guard_on_path() {
	local dir="$1" path="$2" input
	shift 2
	input=$(cd "$dir" && "$@")
	# shellcheck disable=SC2034 # read by the assert_* helpers in helpers/hooks.bash
	GUARD_EXIT=0
	# shellcheck disable=SC2034 # read by the assert_* helpers in helpers/hooks.bash
	GUARD_OUTPUT=$(cd "$dir" && env "PATH=$path" "$BASH_BIN" "$TDD_RED_GUARD_HOOK" <<<"$input" 2>&1 1>/dev/null) || GUARD_EXIT=$?
}

# The guard blocked with output naming the implementation file whose name holds a space.
assert_blocked_naming_spaced_impl() {
	assert_blocked_with_reason "my file.py"
}

@test "red: cat of an implementation file is blocked" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "cat src/mod.py"

	assert_blocked_with_reason "src/mod.py"
}

@test "red: a Read of an implementation file in a repo under a spec/ directory is blocked" {
	touch "$(tdd_marker_path "$SPEC_REPO")"

	run_tdd_guard_read "$SPEC_REPO" "$SPEC_REPO/src/mod.py"

	assert_blocked_with_reason "$SPEC_REPO/src/mod.py"
}

@test "red: cat of an implementation file in a repo under a spec/ directory is blocked" {
	touch "$(tdd_marker_path "$SPEC_REPO")"

	run_tdd_guard "$SPEC_REPO" "cat src/mod.py"

	assert_blocked_with_reason "src/mod.py"
}

@test "red: cat of a test file is allowed" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "cat tests/test_mod.py"

	assert_allowed
}

@test "red: a Read of an implementation file is blocked" {
	touch "$MARKER"

	run_tdd_guard_read "$REPO" "$REPO/src/mod.py"

	assert_blocked_with_reason "$REPO/src/mod.py"
}

@test "gates: without a marker, cat of an implementation file is allowed" {
	rm -f "$MARKER"

	run_tdd_guard "$REPO" "cat src/mod.py"

	assert_allowed
}

@test "gates: under a marker, an agent that is not tdd-cycle reads implementation freely" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "cat src/mod.py" general-purpose

	assert_allowed
}

@test "flags: implementation read after a flag-leading continuation line is blocked" {
	local cmd
	cmd=$(
		cat <<'CMD'
uv run pytest \
  --cov \
  -k foo; cat src/mod.py
CMD
	)
	touch "$MARKER"

	run_tdd_guard "$REPO" "$cmd"

	assert_blocked
}

@test "flags: grep of an implementation file with option words is blocked naming the file" {
	touch "$MARKER"

	run_tdd_guard "$REPO" 'grep -n "def foo" src/mod.py'

	assert_blocked_with_reason "src/mod.py"
}

@test "flags: marker touch after a flag-leading line is mirrored to the per-instance marker" {
	local cmd
	cmd=$(
		cat <<'CMD'
printf x \
  --flag
touch "$(git rev-parse --git-dir)/tdd-red-phase"
CMD
	)
	rm -f "$MARKER"

	run_tdd_guard "$REPO" "$cmd"

	assert_present "$MARKER"
}

@test "quoting: a read of an implementation file is blocked however its path is quoted" {
	touch "$MARKER"

	for_each_case run_tdd_guard "$REPO" -- assert_blocked_naming_spaced_impl -- \
		'cat "src/my file.py"' \
		"cat 'src/my file.py'" \
		'cat src/my\ file.py'
}

@test "cwd: a relative implementation path after cd resolves against the new directory" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "cd src && cat mod.py"

	assert_blocked_with_reason "mod.py"
}

@test "nesting: an implementation read inside bash -c is blocked" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "bash -c 'cat src/mod.py'"

	assert_blocked_with_reason "src/mod.py"
}

@test "flags: marker rm is mirrored to the per-instance marker" {
	touch "$MARKER"

	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	run_tdd_guard "$REPO" 'rm -f "$(git rev-parse --git-dir)/tdd-red-phase"'

	[[ ! -e "$MARKER" ]]
}

@test "flags: marker rm named by a literal path is mirrored to the per-instance marker" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "rm -f .git/tdd-red-phase"

	[[ ! -e "$MARKER" ]]
}

@test "parse: a tdd-cycle command the invocation loop cannot read is blocked" {
	local bin
	bin=$(failing_ils_bin "$BATS_TEST_TMPDIR" 3)
	touch "$MARKER"

	run_tdd_guard_on_path "$REPO" "$bin:$PATH" tdd_hook_input "cat tests/test_mod.py"

	assert_blocked
}

@test "gates: an agent that is not tdd-cycle is allowed without its command being parsed" {
	local bin
	bin=$(failing_ils_bin "$BATS_TEST_TMPDIR" 3)
	touch "$MARKER"

	run_tdd_guard_on_path "$REPO" "$bin:$PATH" tdd_hook_input "cat src/mod.py" general-purpose

	assert_allowed
}

@test "deps: without jq a Bash call is blocked naming jq" {
	touch "$MARKER"

	run_tdd_guard_on_path "$REPO" "$(path_without jq)" tdd_hook_input "cat tests/test_mod.py"

	assert_blocked_with_reason "jq"
}

@test "deps: without jq a Read call is blocked naming jq" {
	touch "$MARKER"

	run_tdd_guard_on_path "$REPO" "$(path_without jq)" tdd_read_hook_input "$REPO/tests/test_mod.py"

	assert_blocked_with_reason "jq"
}
