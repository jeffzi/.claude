#!/usr/bin/env bats

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)
	mkdir -p "$REPO/src" "$REPO/tests"
	printf 'def foo() -> int:\n    return 1\n' >"$REPO/src/mod.py"
	printf 'def test_foo() -> None:\n    assert foo() == 1\n' >"$REPO/tests/test_mod.py"

	export MARKER
	MARKER=$(tdd_marker_path "$REPO")
}

teardown_file() {
	[[ -n "$TMPDIR_ROOT" ]] && rm -rf "$TMPDIR_ROOT"
}

@test "red: cat of an implementation file is blocked" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "cat src/mod.py"

	assert_blocked
	assert_guard_output_includes "BLOCKED (TDD RED phase)"
}

@test "red: cat of a test file is allowed" {
	touch "$MARKER"

	run_tdd_guard "$REPO" "cat tests/test_mod.py"

	assert_allowed
}

@test "red: a Read of an implementation file is blocked" {
	touch "$MARKER"

	run_tdd_guard_read "$REPO" "$REPO/src/mod.py"

	assert_blocked
	assert_guard_output_includes "BLOCKED (TDD RED phase)"
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

@test "flags: grep of an implementation file with option words is blocked with the RED reason" {
	touch "$MARKER"

	run_tdd_guard "$REPO" 'grep -n "def foo" src/mod.py'

	assert_blocked
	assert_guard_output_includes "BLOCKED (TDD RED phase)"
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
