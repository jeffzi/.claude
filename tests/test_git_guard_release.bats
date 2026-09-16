#!/usr/bin/env bats

load helpers/hooks
load helpers/guard

setup_file() {
	export TMPDIR_ROOT
	TMPDIR_ROOT=$(mktemp -d)

	export REPO
	REPO=$(setup_repo repo)

	export RELEASE_MARKED_REPO
	RELEASE_MARKED_REPO=$(setup_release_marked_repo release_marked_repo)

	export RELEASE_STALE_REPO
	RELEASE_STALE_REPO=$(setup_release_marked_repo release_stale_repo)
	backdate_release_marker "$RELEASE_STALE_REPO" "$STALE_OFFSET_MINUTES"

	export RELEASE_FUTURE_REPO
	RELEASE_FUTURE_REPO=$(setup_release_marked_repo release_future_repo)
	backdate_release_marker "$RELEASE_FUTURE_REPO" "$FUTURE_OFFSET_MINUTES"

	export RELEASE_FIXCI_REPO
	RELEASE_FIXCI_REPO=$(setup_fix_ci_repo release_fixci_repo feature/ci)
	raise_release_marker "$RELEASE_FIXCI_REPO"
}

teardown_file() {
	cleanup_tmpdir_root
}

# ── release.sh (user-run) ────────────────────────────────────────────────────

@test "release: invoking the script without a marker is blocked as user-run" {
	# shellcheck disable=SC2088 # the literal tilde is the command under test, not a path this file expands
	run_guard "$REPO" "~/.claude/scripts/release.sh merge"

	assert_blocked
	assert_guard_output_includes "release.sh"
	assert_guard_output_includes "only through /release"
}

@test "release: every quoting, path, and interpreter spelling of the invocation is blocked" {
	# shellcheck disable=SC2088
	each_blocked_in "$REPO" \
		"release.sh merge" \
		"./scripts/release.sh merge" \
		"bash scripts/release.sh merge" \
		'bash "scripts/release.sh"' \
		'"~/.claude/scripts/release.sh" merge' \
		"/bin/bash scripts/release.sh" \
		"/usr/bin/env bash scripts/release.sh" \
		"env release.sh merge" \
		"command bash scripts/release.sh" \
		"exec scripts/release.sh" \
		"FOO=1 scripts/release.sh"
}

@test "release: the invocation is found behind every fragment boundary" {
	local heredoc
	heredoc=$(
		cat <<'CMD'
git commit -m "$(cat <<'EOF'
docs: describe how the plan branch lands
EOF
)" && "scripts/release.sh"
CMD
	)
	# shellcheck disable=SC2088
	each_blocked_in "$REPO" \
		'git commit -m "line one
line two" && bash ~/.claude/scripts/release.sh' \
		'cd /tmp
~/.claude/scripts/release.sh' \
		'git status
bash scripts/release.sh merge' \
		'echo a&"&b" ; bash scripts/release.sh' \
		'git status && "scripts/release.sh"' \
		"$heredoc"
}

@test "release: a message that merely names the script is allowed in every quoting" {
	each_allowed_in "$REPO" \
		'git commit -m "document release.sh"' \
		"git commit -m 'document release.sh'" \
		'git commit -m "notes
release.sh is user-run" && git status' \
		"git commit -m 'notes
release.sh is user-run' && git status"
}

@test "release: a message naming the script with a subcommand is allowed" {
	each_allowed_in "$REPO" \
		'git commit -m "docs: explain release.sh merge"' \
		"git commit -m 'docs: explain release.sh finish'"
}

@test "release: a heredoc-fed commit message naming the script with a subcommand is allowed" {
	run_guard_heredoc <<'CMD'
git commit -m "$(cat <<'EOF'
docs: explain how release.sh finish tags the release
EOF
)"
CMD

	assert_allowed
}

@test "release: reading, linting, formatting, chmod, and bats on the script are allowed" {
	each_allowed_in "$REPO" \
		"cat scripts/release.sh" \
		"shellcheck -x scripts/release.sh" \
		"shfmt -d scripts/release.sh" \
		"chmod +x scripts/release.sh" \
		"bats tests/test_release_start.bats"
}

@test "release: the status subcommand needs no marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$REPO" \
		"~/.claude/scripts/release.sh status" \
		"bash scripts/release.sh status" \
		"release.sh status"
}

@test "release: status past the first argument does not exempt the invocation" {
	each_blocked_in "$REPO" \
		"release.sh merge status" \
		"bash scripts/release.sh --skip-ci status"
}

@test "release: a subcommand makes it an invocation whatever words precede it" {
	# shellcheck disable=SC2088
	each_blocked_for_in "only through /release" "$REPO" \
		"timeout 5 scripts/release.sh merge" \
		"xargs release.sh merge" \
		"uv run release.sh merge" \
		"uv run ~/.claude/scripts/release.sh finish --check" \
		"nice -n 5 release.sh start 1.2.0"
}

@test "release: status behind a preceding word still needs no marker" {
	each_allowed_in "$REPO" \
		"timeout 5 release.sh status" \
		"uv run scripts/release.sh status"
}

@test "release: an invocation behind a preceding word is allowed under a fresh marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$RELEASE_MARKED_REPO" \
		"timeout 5 scripts/release.sh merge" \
		"uv run ~/.claude/scripts/release.sh finish --check" \
		"nice -n 5 release.sh start 1.2.0"
}

@test "release: every invocation spelling is allowed under a fresh marker" {
	# shellcheck disable=SC2088
	each_allowed_in "$RELEASE_MARKED_REPO" \
		"~/.claude/scripts/release.sh" \
		"bash scripts/release.sh merge" \
		'"~/.claude/scripts/release.sh" merge'
}

@test "release: invoking the script under a stale or future-dated marker is blocked" {
	local dir
	for dir in "$RELEASE_STALE_REPO" "$RELEASE_FUTURE_REPO"; do
		run_guard "$dir" "bash scripts/release.sh merge"

		if ! assert_blocked || ! assert_guard_output_includes "only through /release"; then
			printf 'repo: %s\n' "$dir" >&2
			return 1
		fi
	done
}

@test "release: force-with-lease under the release marker alone is blocked as an unsanctioned push" {
	run_guard "$RELEASE_MARKED_REPO" "git push --force-with-lease"

	assert_blocked
	assert_guard_output_includes "Automatic git push is not allowed"
}

@test "release: force-with-lease under both markers is blocked as a history rewrite" {
	run_guard "$RELEASE_FIXCI_REPO" "git push --force-with-lease"

	assert_blocked
	assert_guard_output_includes "never rewrites history"
}

# ── Shared constants ─────────────────────────────────────────────────────────

@test "shared constant: branch-policy.sh exposes the release marker file and config key" {
	local want="release-active release" got

	got=$(bash -c '. "$1"; printf "%s %s" "$RELEASE_MARKER" "$RELEASE_KEY"' _ "$BRANCH_POLICY_LIB")

	[[ "$got" == "$want" ]] || {
		printf 'RELEASE_MARKER/RELEASE_KEY are "%s", expected "%s"\n' "$got" "$want" >&2
		return 1
	}
}
