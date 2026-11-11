#!/usr/bin/env bats

# Records read as `tool|git dir|subcommand|dir|word count|word|…|`, one `|`
# per NUL field terminator (see run_ils_invocations); a literal word reads
# `=<text>`, a non-literal one `?`.

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

# Runs ils_each_invocation with a no-op callback on a hook payload for command $2
# from cwd $1, with PATH $3 (default the current PATH) for the child alone; sets
# RUN_EXIT, RUN_STDOUT, RUN_STDERR.
run_each_invocation() {
	local dir="$1" cmd="$2" path="${3:-$PATH}" input
	input=$(bash_hook_input "$cmd" "$dir")
	# shellcheck disable=SC2016 # the child bash expands its own positional args
	run_capture "$dir" env "PATH=$path" "$BASH_BIN" -c \
		'source "$1" && source "$2" && ils_each_invocation :' \
		_ "$PROJECT_DIR/scripts/sh-common.sh" "$ILS_INVOCATIONS_SCRIPT" <<<"$input"
}

# Runs loop $3 (ils_each_invocation or ils_each_git_invocation) with the
# callback `cb` that shell code $4 defines, on a hook payload for command $2
# from cwd $1; sets RUN_EXIT, RUN_STDOUT, RUN_STDERR.
run_loop_with_callback() {
	local dir="$1" cmd="$2" loop="$3" callback="$4" input
	input=$(bash_hook_input "$cmd" "$dir")
	# shellcheck disable=SC2016 # the child bash expands its own positional args
	run_capture "$dir" "$BASH_BIN" -c \
		'source "$1" && source "$2" && eval "$4" && "$3" cb' \
		_ "$PROJECT_DIR/scripts/sh-common.sh" "$ILS_INVOCATIONS_SCRIPT" "$loop" "$callback" <<<"$input"
}

@test "non-literal words are marked, never yielded as text, in git arguments and gh words" {
	# shellcheck disable=SC2016 # the literal expansions are the command text under test
	run_ils_invocations "$REPO" 'git add "$f" README && gh pr edit "$(cat n)" --add-label x'

	assert_run_ok
	[[ "$RUN_STDOUT" == "git|$REPO_GIT_DIR|add|$REPO|2|?|=README|gh|||$REPO|6|=gh|=pr|=edit|?|=--add-label|=x||||$REPO|2|=cat|=n|" ]]
}

@test "other commands: yields a record with an empty tool and every marked word, inside a pipeline and bash -c" {
	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	local cmd='cat README | head -n 1; bash -c '\''wc -l "$f"'\'''
	local want="|||$REPO|2|=cat|=README|"
	want+="|||$REPO|3|=head|=-n|=1|"
	want+="|||$REPO|3|=bash|=-c|=wc -l \"\$f\"|"
	want+="|||$REPO|3|=wc|=-l|?|"

	run_ils_invocations "$REPO" "$cmd"

	assert_run_ok
	[[ "$RUN_STDOUT" == "$want" ]]
}

@test "git: a non-literal or missing subcommand yields an empty subcommand" {
	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	run_ils_invocations "$REPO" 'git com"$sub" README; git'

	assert_run_ok
	[[ "$RUN_STDOUT" == "git|$REPO_GIT_DIR||$REPO|1|=README|git|$REPO_GIT_DIR||$REPO|0|" ]]
}

@test "git dir: an invocation outside any repository yields an empty git dir" {
	run_ils_invocations "$OUTSIDE_DIR" "git status"

	assert_run_ok
	[[ "$RUN_STDOUT" == "git||status|$OUTSIDE_DIR|0|" ]]
}

@test "git dir: an invocation whose git dir is unknown yields an empty git dir" {
	# shellcheck disable=SC2016 # the literal expansions are the command text under test
	run_ils_invocations "$REPO" 'git -C "$d" status'

	assert_run_ok
	[[ "$RUN_STDOUT" == "git||status|$REPO|0|" ]]
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

@test "each invocation: jq missing from PATH exits 2 naming jq" {
	run_each_invocation "$REPO" "git status" "$(path_without jq)"

	assert_run_failed 2
	assert_reason_names_program jq
}

@test "each invocation: ils parse exiting with neither 0 nor 1 exits 2 naming its exit status" {
	local bin
	bin=$(failing_ils_bin "$TMPDIR_ROOT/broken_each_ils" 42)

	run_each_invocation "$REPO" "git status" "$bin:$PATH"

	assert_run_failed 2
	assert_reason "42"
}

@test "each invocation: a command that is neither git, gh nor ils reaches the callback with an empty tool" {
	# shellcheck disable=SC2016 # the callback expands its own positional args
	run_loop_with_callback "$REPO" "cat README" ils_each_invocation \
		'cb() { printf "[%s|%s|%s|%s]" "$1" "$2" "$3" "$4"; }'

	assert_run_ok
	[[ "$RUN_STDOUT" == "[|||$REPO]" ]]
}

@test "each invocation: a callback that reads stdin does not swallow the invocations after it" {
	# shellcheck disable=SC2016 # the callback expands its own positional args
	run_loop_with_callback "$REPO" "git status && git log" ils_each_invocation \
		'cb() { cat >/dev/null; printf "%s\n" "$3"; }'

	assert_run_ok
	[[ "$RUN_STDOUT" == $'status\nlog' ]]
}

@test "each git invocation: skips a git invocation outside any repository or with an unknown git dir" {
	# shellcheck disable=SC2016 # the literal expansion is the command text under test
	local cmd="git status; git -C $OUTSIDE_DIR log; git -C \"\$d\" diff; git -C $REPO show"

	# shellcheck disable=SC2016 # the callback expands its own positional args
	run_loop_with_callback "$OUTSIDE_DIR" "$cmd" ils_each_git_invocation \
		'cb() { printf "%s\n" "$1"; }'

	assert_run_ok
	[[ "$RUN_STDOUT" == "$REPO_GIT_DIR" ]]
}

# Runs ils_each_invocation in a child that opted into the fail-closed EXIT
# handler, with the callback `cb` whose body is the second word onward of case
# $1, on `git status` from $REPO, under bash binary $HOOK_BASH (default
# $BASH_BIN) with a fresh TMPDIR; sets RUN_EXIT, RUN_STDOUT, RUN_STDERR and
# CASE_TMPDIR.
run_fail_closed_each_invocation() {
	local input
	input=$(bash_hook_input "git status" "$REPO")
	CASE_TMPDIR=$(mktemp -d "$TMPDIR_ROOT/records.XXXXXX")
	# shellcheck disable=SC2016 # the child bash expands its own positional args
	run_capture "$REPO" env "TMPDIR=$CASE_TMPDIR" "${HOOK_BASH:-$BASH_BIN}" -c \
		'PROG=fail-closed-test; source "$1" && source "$2" && sh_fail_closed && eval "cb() { $3; }" && ils_each_invocation cb' \
		_ "$PROJECT_DIR/scripts/sh-common.sh" "$ILS_INVOCATIONS_SCRIPT" "${1#* }" <<<"$input"
}

# The run of case $1 ("<exit> <callback body>") exited with the case's exit
# and left no record file behind in its TMPDIR.
assert_exit_without_records() {
	local leftover
	assert_run_failed "${1%% *}" || return 1
	leftover=$(ls -A "$CASE_TMPDIR")
	[[ -z "$leftover" ]] || {
		printf 'record files left in TMPDIR: %s\n' "$leftover" >&2
		return 1
	}
}

each_fail_closed_invocation() {
	for_each_case run_fail_closed_each_invocation -- assert_exit_without_records -- \
		"0 :" \
		"2 exit 2" \
		"2 exit 1"
}

@test "fail closed: an allow, a block or an unexpected exit 1 from the callback keeps its verdict and removes the record file" {
	each_fail_closed_invocation
}

@test "fail closed: under bash 3.2 an allow, a block or an unexpected exit 1 keeps its verdict and removes the record file" {
	HOOK_BASH=/bin/bash each_fail_closed_invocation
}
