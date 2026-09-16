#!/usr/bin/env bash
# Shared fixture builders and command-list assertions for the
# tests/test_git_guard_*.bats suites. Loaded after helpers/hooks, whose repo
# builders, marker helpers, and run_guard/assert_* functions these call.

# Repo with a tdd-cycle marker raised; prints the repo dir.
setup_tdd_active_repo() {
	local dir
	dir=$(setup_repo "$1")
	touch "$(git -C "$dir" rev-parse --absolute-git-dir)/tdd-cycle-active"
	printf '%s' "$dir"
}

# Leave an untracked plan file in the repo at $1.
add_untracked_plan() {
	mkdir -p "$1/.claude/plans"
	printf 'plan content\n' >"$1/.claude/plans/phase.md"
}

# Repo with a fresh release marker raised; prints the repo dir.
setup_release_marked_repo() {
	local dir
	dir=$(setup_repo "$1")
	raise_release_marker "$dir"
	printf '%s' "$dir"
}

# Every command in the list is blocked in repo $1; a failure names the command.
each_blocked_in() {
	local dir="$1" cmd
	shift
	for cmd in "$@"; do
		run_guard "$dir" "$cmd"
		assert_blocked || {
			printf 'command: %s\n' "$cmd" >&2
			return 1
		}
	done
}

# Every command in the list is blocked in repo $2 with output naming reason $1;
# a failure names the command.
each_blocked_for_in() {
	local reason="$1" dir="$2" cmd
	shift 2
	for cmd in "$@"; do
		run_guard "$dir" "$cmd"
		{ assert_blocked && assert_guard_output_includes "$reason"; } || {
			printf 'command: %s\n' "$cmd" >&2
			return 1
		}
	done
}

# Every command in the list is allowed in repo $1; a failure names the command.
each_allowed_in() {
	local dir="$1" cmd
	shift
	for cmd in "$@"; do
		run_guard "$dir" "$cmd"
		assert_allowed || {
			printf 'command: %s\n' "$cmd" >&2
			return 1
		}
	done
}

# run_guard on the command read from stdin — for commands that embed their own
# nested heredoc, which a bats argument cannot spell directly.
run_guard_heredoc() {
	local cmd
	cmd=$(cat)
	run_guard "$REPO" "$cmd"
}
