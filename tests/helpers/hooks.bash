#!/usr/bin/env bash
# Shared helpers for hook and wrapper test suites (bats).

HELPERS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly HELPERS_DIR
PROJECT_DIR=$(cd "$HELPERS_DIR/../.." && pwd)
readonly PROJECT_DIR

readonly GIT_GUARD_HOOK="$PROJECT_DIR/hooks/git-guard.sh"
readonly GIT_COMMIT_GUARD_HOOK="$PROJECT_DIR/hooks/git-commit-guard.sh"
readonly FIX_CI_PUSH_WRAPPER="$PROJECT_DIR/scripts/fix-ci-push.sh"
BASH_BIN=$(command -v bash)
readonly BASH_BIN

# ── Hook invocation ──────────────────────────────────────────────────────────

hook_input() {
	jq -n --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

# Run git-guard hook in $1 with command $2; sets GUARD_EXIT and GUARD_OUTPUT.
run_guard() {
	local dir="$1" cmd="$2"
	GUARD_EXIT=0
	GUARD_OUTPUT=$(cd "$dir" && hook_input "$cmd" | bash "$GIT_GUARD_HOOK" 2>&1 1>/dev/null) || GUARD_EXIT=$?
}

# Run git-commit-guard hook with command $1; sets GUARD_EXIT and GUARD_OUTPUT.
run_commit_guard() {
	local cmd="$1"
	GUARD_EXIT=0
	GUARD_OUTPUT=$(hook_input "$cmd" | bash "$GIT_COMMIT_GUARD_HOOK" 2>&1) || GUARD_EXIT=$?
}

# ── Guard assertions ─────────────────────────────────────────────────────────

assert_blocked() {
	((GUARD_EXIT == 2)) || {
		printf 'expected exit 2 (blocked), got %d\noutput: %s\n' "$GUARD_EXIT" "$GUARD_OUTPUT" >&2
		return 1
	}
}

assert_allowed() {
	((GUARD_EXIT == 0)) || {
		printf 'expected exit 0 (allowed), got %d\noutput: %s\n' "$GUARD_EXIT" "$GUARD_OUTPUT" >&2
		return 1
	}
}

assert_absent() {
	local path="$1"
	[[ ! -e "$path" ]] || {
		printf 'still present: %s\n' "$path" >&2
		return 1
	}
}

# ── Fix-ci-push invocation ───────────────────────────────────────────────────

# Run fix-ci-push.sh from $1 with remaining args; sets WRAPPER_EXIT and WRAPPER_STDERR.
run_wrapper() {
	local dir="$1"
	shift
	WRAPPER_EXIT=0
	WRAPPER_STDERR=$(cd "$dir" && "$FIX_CI_PUSH_WRAPPER" "$@" 2>&1 1>/dev/null) || WRAPPER_EXIT=$?
}

# Run fix-ci-push.sh with empty PATH; sets WRAPPER_EXIT and WRAPPER_STDERR.
run_wrapper_without_git() {
	WRAPPER_EXIT=0
	WRAPPER_STDERR=$(env PATH=/var/empty "$BASH_BIN" "$FIX_CI_PUSH_WRAPPER" "$@" 2>&1 1>/dev/null) || WRAPPER_EXIT=$?
}

# ── Wrapper assertions ───────────────────────────────────────────────────────

assert_refused() {
	((WRAPPER_EXIT == 2)) && [[ -n "$WRAPPER_STDERR" ]] || {
		printf 'expected exit 2 with stderr, got exit %d\nstderr: %s\n' "$WRAPPER_EXIT" "$WRAPPER_STDERR" >&2
		return 1
	}
}

assert_pushed() {
	((WRAPPER_EXIT == 0)) || {
		printf 'expected exit 0, got %d\nstderr: %s\n' "$WRAPPER_EXIT" "$WRAPPER_STDERR" >&2
		return 1
	}
}

assert_failed() {
	((WRAPPER_EXIT != 0)) || {
		printf 'expected non-zero exit, got 0\nstderr: %s\n' "$WRAPPER_STDERR" >&2
		return 1
	}
}

assert_reason() {
	local pattern="$1"
	((WRAPPER_EXIT != 0)) && [[ "$WRAPPER_STDERR" == *"$pattern"* ]] || {
		printf 'expected non-zero exit with "%s" in stderr\nexit: %d\nstderr: %s\n' \
			"$pattern" "$WRAPPER_EXIT" "$WRAPPER_STDERR" >&2
		return 1
	}
}

assert_ref_at() {
	local bare="$1" ref="$2" want="$3"
	local got
	got=$(git -C "$bare" rev-parse "refs/heads/$ref" 2>/dev/null) || got="<missing>"
	[[ "$got" == "$want" ]] || {
		printf 'refs/heads/%s is %s, expected %s\n' "$ref" "$got" "$want" >&2
		return 1
	}
}

assert_ref_present() {
	local bare="$1" ref="$2"
	git -C "$bare" show-ref --quiet --verify "refs/heads/$ref" || {
		printf 'refs/heads/%s missing from %s\n' "$ref" "$bare" >&2
		return 1
	}
}

assert_ref_absent() {
	local bare="$1" ref="$2"
	! git -C "$bare" show-ref --quiet --verify "refs/heads/$ref" || {
		printf 'refs/heads/%s present in %s\n' "$ref" "$bare" >&2
		return 1
	}
}

# ── Cross-platform date offset ──────────────────────────────────────────────

# date_offset_minutes <signed-int> <fmt>
# Example: date_offset_minutes -31 +%Y%m%d%H%M
date_offset_minutes() {
	local minutes="$1" fmt="$2"
	if date -v-1S +%s >/dev/null 2>&1; then
		date "-v${minutes}M" "$fmt"
	else
		date -d "${minutes} minutes" "$fmt"
	fi
}

# ── Fixture builders ─────────────────────────────────────────────────────────
# All builders create directories under $TMPDIR_ROOT (set by the caller's setup_file).

init_git_identity() {
	git -C "$1" config user.email "test@test.com"
	git -C "$1" config user.name "Test"
}

commit_readme() {
	local dir="$1"
	touch "$dir/README"
	git -C "$dir" add README
	git -C "$dir" -c commit.gpgsign=false commit -q -m "init"
}

setup_repo() {
	local dir="$TMPDIR_ROOT/$1"
	mkdir -p "$dir"
	git -C "$dir" init -q
	init_git_identity "$dir"
	commit_readme "$dir"
	printf '%s' "$dir"
}

# Add worktree $2 under $1/.claude/worktrees; prints the worktree path.
add_worktree() {
	local repo="$1" name="$2"
	local path="$repo/.claude/worktrees/$name"
	git -C "$repo" worktree add -q -b "wt-$name" "$path"
	printf '%s' "$path"
}

setup_fix_ci_repo() {
	local dir
	dir=$(setup_repo "$1")
	git -C "$dir" branch -M "$2"
	touch "$(git -C "$dir" rev-parse --absolute-git-dir)/fix-ci-active"
	printf '%s' "$dir"
}

# Work repo on main with a local fix-ci/lint branch, wired to a local bare origin.
# Prints the work dir; the bare origin is always "<work>/../origin.git".
setup_pair() {
	local base="$TMPDIR_ROOT/$1"
	local work="$base/work"
	mkdir -p "$base"
	git init -q --bare --initial-branch=main "$base/origin.git"
	git init -q --initial-branch=main "$work"
	init_git_identity "$work"
	commit_readme "$work"
	git -C "$work" branch fix-ci/lint
	git -C "$work" remote add origin "$base/origin.git"
	printf '%s' "$work"
}

bare_of() {
	printf '%s' "${1%/work}/origin.git"
}

seed_origin() {
	local work="$1"
	shift
	local ref
	for ref in "$@"; do
		git -C "$(bare_of "$work")" fetch -q "$work" "refs/heads/$ref:refs/heads/$ref"
	done
}

raise_marker() {
	touch "$(git -C "$1" rev-parse --absolute-git-dir)/fix-ci-active"
}

marker_path() {
	printf '%s/fix-ci-active' "$(git -C "$1" rev-parse --absolute-git-dir)"
}

# One minute past the marker's 30-minute freshness TTL, and 60 minutes ahead
# for clock-skew coverage (see fix-ci-policy.sh's FIX_CI_MARKER_TTL_SECONDS).
export STALE_OFFSET_MINUTES=-31
readonly STALE_OFFSET_MINUTES
export FUTURE_OFFSET_MINUTES=+60
readonly FUTURE_OFFSET_MINUTES

backdate_marker() {
	touch -t "$(date_offset_minutes "$2" +%Y%m%d%H%M)" "$(marker_path "$1")"
}
