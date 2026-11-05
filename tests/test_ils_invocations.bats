#!/usr/bin/env bats

# Records read as `tool|git dir|subcommand|argument count|argument|…|`, one
# `|` per NUL field terminator (see run_ils_invocations).

load helpers/hooks

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export REPO_GIT_DIR
	REPO_GIT_DIR=$(git -C "$REPO" rev-parse --absolute-git-dir)

	export OUTSIDE_DIR="$TMPDIR_ROOT/outside"
	mkdir -p "$OUTSIDE_DIR"
}

teardown_file() {
	cleanup_tmpdir_root
}

@test "git: yields one record per git invocation, after cd, behind -C, inside \$(…) and bash -c" {
	local cmd="cd $REPO && git commit -m 'first line'; echo \"\$(git rev-parse HEAD)\"; bash -c 'git status --short'; cd $OUTSIDE_DIR; git -C $REPO add 'my notes.md'"

	run_ils_invocations "$OUTSIDE_DIR" "$cmd"

	assert_run_ok
	[[ "$RUN_STDOUT" == "git|$REPO_GIT_DIR|commit|2|-m|first line|git|$REPO_GIT_DIR|rev-parse|1|HEAD|git|$REPO_GIT_DIR|status|1|--short|git|$REPO_GIT_DIR|add|1|my notes.md|" ]]
}

@test "git: an empty literal argument is yielded and counted" {
	run_ils_invocations "$REPO" "git commit -m ''"

	assert_run_ok
	[[ "$RUN_STDOUT" == "git|$REPO_GIT_DIR|commit|2|-m||" ]]
}

@test "gh: yields one record per gh invocation with its literal words" {
	run_ils_invocations "$REPO" "gh pr create --title 'a b' && gh pr edit 12"

	assert_run_ok
	[[ "$RUN_STDOUT" == "gh|||5|gh|pr|create|--title|a b|gh|||4|gh|pr|edit|12|" ]]
}

@test "non-literal words are left out of git arguments and gh words" {
	# shellcheck disable=SC2016 # the literal expansions are the command text under test
	run_ils_invocations "$REPO" 'git add "$f" README && gh pr edit "$(cat n)" --add-label x'

	assert_run_ok
	[[ "$RUN_STDOUT" == "git|$REPO_GIT_DIR|add|1|README|gh|||5|gh|pr|edit|--add-label|x|" ]]
}

@test "git: a non-literal or missing subcommand yields an empty subcommand" {
	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	run_ils_invocations "$REPO" 'git com"$sub" README; git'

	assert_run_ok
	[[ "$RUN_STDOUT" == "git|$REPO_GIT_DIR||1|README|git|$REPO_GIT_DIR||0|" ]]
}

@test "git dir: an invocation outside any repository yields an empty git dir" {
	run_ils_invocations "$OUTSIDE_DIR" "git status"

	assert_run_ok
	[[ "$RUN_STDOUT" == "git||status|0|" ]]
}

@test "git dir: an invocation whose git dir is unknown yields an empty git dir" {
	# shellcheck disable=SC2016 # the literal expansions are the command text under test
	run_ils_invocations "$REPO" 'git -C "$d" status'

	assert_run_ok
	[[ "$RUN_STDOUT" == "git||status|0|" ]]
}

@test "a command that does not parse yields nothing and succeeds" {
	run_ils_invocations "$REPO" 'git commit -m "unterminated'

	assert_run_ok
	[[ -z "$RUN_STDOUT" ]]
}

@test "ils missing from PATH fails naming ils" {
	run_ils_invocations "$REPO" "git status" "$(path_without ils)"

	assert_reason_names_program ils
	[[ -z "$RUN_STDOUT" ]]
}

@test "jq missing from PATH fails naming jq" {
	run_ils_invocations "$REPO" "git status" "$(path_without jq)"

	assert_reason_names_program jq
	[[ -z "$RUN_STDOUT" ]]
}

@test "ils parse exiting with neither 0 nor 1 fails naming its exit status" {
	local bin
	bin=$(failing_ils_bin "$TMPDIR_ROOT/broken_ils" 42)

	run_ils_invocations "$REPO" "git status" "$bin:$PATH"

	assert_reason "42"
	[[ -z "$RUN_STDOUT" ]]
}
