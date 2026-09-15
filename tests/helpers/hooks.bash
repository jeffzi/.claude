#!/usr/bin/env bash
# Shared helpers for hook and wrapper test suites (bats).

HELPERS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly HELPERS_DIR
PROJECT_DIR=$(cd "$HELPERS_DIR/../.." && pwd)
readonly PROJECT_DIR

readonly GIT_GUARD_HOOK="$PROJECT_DIR/hooks/git-guard.sh"
readonly GIT_LOCK_GUARD_HOOK="$PROJECT_DIR/hooks/git-lock-guard.sh"
readonly GIT_COMMIT_GUARD_HOOK="$PROJECT_DIR/hooks/git-commit-guard.sh"
readonly TDD_RED_GUARD_HOOK="$PROJECT_DIR/hooks/tdd-red-guard.sh"
readonly FIX_CI_PUSH_WRAPPER="$PROJECT_DIR/scripts/fix-ci-push.sh"
# shellcheck disable=SC2034 # consumed by test_plan_branch.bats, which loads this file
readonly PLAN_BRANCH_SCRIPT="$PROJECT_DIR/scripts/plan-branch.sh"
# shellcheck disable=SC2034 # consumed by test_plan_branch.bats, which loads this file
readonly BRANCH_POLICY_LIB="$PROJECT_DIR/scripts/branch-policy.sh"
# shellcheck disable=SC2034 # consumed by test_release.bats, which loads this file
readonly RELEASE_SCRIPT="$PROJECT_DIR/scripts/release.sh"
BASH_BIN=$(command -v bash)
readonly BASH_BIN

# Every git call a suite makes — fixture builders and the hooks under test
# alike — sees repo-local config only, so a developer's own ~/.gitconfig
# (claude.protectMain, init.defaultBranch, commit.gpgsign) cannot change a
# verdict.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

# ── Suite teardown ───────────────────────────────────────────────────────────

# Removes the suite's TMPDIR_ROOT; the shared body for every file's
# teardown/teardown_file, which bats requires to keep that exact name locally.
cleanup_tmpdir_root() {
	[[ -n "$TMPDIR_ROOT" ]] && rm -rf "$TMPDIR_ROOT"
}

# ── Hook invocation ──────────────────────────────────────────────────────────

hook_input() {
	jq -n --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd}}'
}

# Run hook script $1 in $2 with command $3; sets GUARD_EXIT and GUARD_OUTPUT.
run_hook_for_command() {
	local hook="$1" dir="$2" cmd="$3"
	GUARD_EXIT=0
	GUARD_OUTPUT=$(cd "$dir" && hook_input "$cmd" | bash "$hook" 2>&1 1>/dev/null) || GUARD_EXIT=$?
}

# Run git-guard hook in $1 with command $2; sets GUARD_EXIT and GUARD_OUTPUT.
run_guard() {
	run_hook_for_command "$GIT_GUARD_HOOK" "$1" "$2"
}

# Run git-lock-guard hook in $1 with command $2; sets GUARD_EXIT and GUARD_OUTPUT.
run_lock_guard() {
	run_hook_for_command "$GIT_LOCK_GUARD_HOOK" "$1" "$2"
}

# Run git-commit-guard hook with command $1; sets GUARD_EXIT and GUARD_OUTPUT.
run_commit_guard() {
	local cmd="$1"
	GUARD_EXIT=0
	GUARD_OUTPUT=$(hook_input "$cmd" | bash "$GIT_COMMIT_GUARD_HOOK" 2>&1) || GUARD_EXIT=$?
}

# Agent id every run_tdd_guard call carries; fixes the per-instance marker path.
export TDD_AGENT_ID="tdd-cycle-test-agent"
readonly TDD_AGENT_ID

# Bash payload for the tdd-red-guard hook: command $1 from agent type $2
# (default tdd-cycle, the only type the hook gates).
tdd_hook_input() {
	jq -n --arg cmd "$1" --arg id "$TDD_AGENT_ID" --arg type "${2:-tdd-cycle}" \
		'{"tool_name":"Bash","tool_input":{"command":$cmd},"agent_type":$type,"agent_id":$id}'
}

# Read payload for the tdd-red-guard hook: file $1 read by a tdd-cycle agent.
tdd_read_hook_input() {
	jq -n --arg path "$1" --arg id "$TDD_AGENT_ID" \
		'{"tool_name":"Read","tool_input":{"file_path":$path},"agent_type":"tdd-cycle","agent_id":$id}'
}

# Run tdd-red-guard hook in $1 with Bash command $2 from agent type $3 (default
# tdd-cycle); sets GUARD_EXIT and GUARD_OUTPUT.
run_tdd_guard() {
	local dir="$1" cmd="$2" type="${3:-tdd-cycle}"
	GUARD_EXIT=0
	GUARD_OUTPUT=$(cd "$dir" && tdd_hook_input "$cmd" "$type" | bash "$TDD_RED_GUARD_HOOK" 2>&1 1>/dev/null) || GUARD_EXIT=$?
}

# Run tdd-red-guard hook in $1 for a Read of $2; sets GUARD_EXIT and GUARD_OUTPUT.
run_tdd_guard_read() {
	local dir="$1" path="$2"
	GUARD_EXIT=0
	GUARD_OUTPUT=$(cd "$dir" && tdd_read_hook_input "$path" | bash "$TDD_RED_GUARD_HOOK" 2>&1 1>/dev/null) || GUARD_EXIT=$?
}

# Path of the per-instance RED-phase marker the hook gates on, for the repo at $1.
tdd_marker_path() {
	printf '%s/tdd-red-phase.%s' "$(git -C "$1" rev-parse --absolute-git-dir)" "$TDD_AGENT_ID"
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

assert_present() {
	local path="$1"
	[[ -e "$path" ]] || {
		printf 'missing: %s\n' "$path" >&2
		return 1
	}
}

assert_guard_output_includes() {
	local pattern="$1"
	[[ "$GUARD_OUTPUT" == *"$pattern"* ]] || {
		printf 'missing "%s" in output: %s\n' "$pattern" "$GUARD_OUTPUT" >&2
		return 1
	}
}

assert_guard_output_excludes() {
	local pattern="$1"
	[[ "$GUARD_OUTPUT" != *"$pattern"* ]] || {
		printf 'unexpected "%s" in output: %s\n' "$pattern" "$GUARD_OUTPUT" >&2
		return 1
	}
}

# ── Script invocation ────────────────────────────────────────────────────────
# One runner for every executable under test. Streams stay apart: refusals and
# diagnostics land on stderr, a script's success line on stdout.

# Run $2 with its args from $1; sets RUN_EXIT, RUN_STDOUT, RUN_STDERR.
run_script() {
	local dir="$1"
	shift
	run_script_on_path "$dir" "$PATH" "$@"
}

# Same as run_script, with PATH set to $2 for the child.
run_script_on_path() {
	local dir="$1" path="$2" err
	shift 2
	err=$(mktemp)
	RUN_EXIT=0
	RUN_STDOUT=$(cd "$dir" && env "PATH=$path" "$@" 2>"$err") || RUN_EXIT=$?
	RUN_STDERR=$(<"$err")
	rm -f "$err"
}

# Run fix-ci-push.sh from $1 with remaining args.
run_wrapper() {
	local dir="$1"
	shift
	run_script "$dir" "$FIX_CI_PUSH_WRAPPER" "$@"
}

# Writes a `stat` under $1/bin that answers neither the BSD nor the GNU dialect,
# and prints that bin dir for prepending to PATH.
failing_stat_bin() {
	local bin="$1/bin"
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$bin/stat"
	chmod +x "$bin/stat"
	printf '%s' "$bin"
}

# Run fix-ci-push.sh from $1 with an empty PATH, so no git can be found.
run_wrapper_without_git() {
	local dir="$1"
	shift
	run_script_on_path "$dir" /var/empty "$BASH_BIN" "$FIX_CI_PUSH_WRAPPER" "$@"
}

# ── Script assertions ────────────────────────────────────────────────────────

assert_run_ok() {
	((RUN_EXIT == 0)) || {
		printf 'expected exit 0, got %d\nstderr: %s\n' "$RUN_EXIT" "$RUN_STDERR" >&2
		return 1
	}
}

assert_refused() {
	((RUN_EXIT == 2)) && [[ -n "$RUN_STDERR" ]] || {
		printf 'expected exit 2 with stderr, got exit %d\nstderr: %s\n' "$RUN_EXIT" "$RUN_STDERR" >&2
		return 1
	}
}

# The run ended with exactly exit $1.
assert_run_failed() {
	local want="$1"
	((RUN_EXIT == want)) || {
		printf 'expected exit %d, got %d\nstdout: %s\nstderr: %s\n' "$want" "$RUN_EXIT" "$RUN_STDOUT" "$RUN_STDERR" >&2
		return 1
	}
}

assert_reason() {
	local pattern="$1"
	((RUN_EXIT != 0)) && [[ "$RUN_STDERR" == *"$pattern"* ]] || {
		printf 'expected non-zero exit with "%s" in stderr\nexit: %d\nstderr: %s\n' \
			"$pattern" "$RUN_EXIT" "$RUN_STDERR" >&2
		return 1
	}
}

assert_stdout_includes() {
	local pattern="$1"
	[[ "$RUN_STDOUT" == *"$pattern"* ]] || {
		printf 'missing "%s" in stdout: %s\n' "$pattern" "$RUN_STDOUT" >&2
		return 1
	}
}

assert_stdout_excludes() {
	local pattern="$1"
	[[ "$RUN_STDOUT" != *"$pattern"* ]] || {
		printf 'unexpected "%s" in stdout: %s\n' "$pattern" "$RUN_STDOUT" >&2
		return 1
	}
}

assert_stderr_includes() {
	local pattern="$1"
	[[ "$RUN_STDERR" == *"$pattern"* ]] || {
		printf 'missing "%s" in stderr: %s\n' "$pattern" "$RUN_STDERR" >&2
		return 1
	}
}

assert_stderr_excludes() {
	local pattern="$1"
	[[ "$RUN_STDERR" != *"$pattern"* ]] || {
		printf 'unexpected "%s" in stderr: %s\n' "$pattern" "$RUN_STDERR" >&2
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

# Revision expression $2 in repo $1 resolves to $3.
assert_rev_at() {
	local repo="$1" rev="$2" want="$3" got
	got=$(git -C "$repo" rev-parse "$rev" 2>/dev/null) || got="<missing>"
	[[ "$got" == "$want" ]] || {
		printf '%s is %s, expected %s\n' "$rev" "$got" "$want" >&2
		return 1
	}
}

assert_ref_present() {
	local repo="$1" ref="$2"
	git -C "$repo" show-ref --quiet --verify "refs/heads/$ref" || {
		printf 'refs/heads/%s missing from %s\n' "$ref" "$repo" >&2
		return 1
	}
}

assert_ref_absent() {
	local repo="$1" ref="$2"
	! git -C "$repo" show-ref --quiet --verify "refs/heads/$ref" || {
		printf 'refs/heads/%s present in %s\n' "$ref" "$repo" >&2
		return 1
	}
}

# The run printed exactly the usage line on stdout, nothing on stderr, and exited 0.
# Relies on $USAGE_LINE, which each spec file defines for its own script.
assert_help_printed() {
	((RUN_EXIT == 0)) && [[ "$RUN_STDOUT" == "$USAGE_LINE" && -z "$RUN_STDERR" ]] || {
		printf 'expected exit 0 with only the usage line on stdout\nexit: %d\nstdout: %s\nstderr: %s\n' \
			"$RUN_EXIT" "$RUN_STDOUT" "$RUN_STDERR" >&2
		return 1
	}
}

assert_on_branch() {
	local got
	got=$(git -C "$1" symbolic-ref --short HEAD)
	[[ "$got" == "$2" ]] || {
		printf 'on branch %s, expected %s\n' "$got" "$2" >&2
		return 1
	}
}

# Repo $1 still matches the repo_state() snapshot $2. Relies on repo_state,
# which each spec file defines to cover what its own script could change.
assert_repo_state() {
	local repo="$1" want="$2" got
	got=$(repo_state "$repo")
	[[ "$got" == "$want" ]] || {
		printf 'repo state changed:\n%s\nexpected:\n%s\n' "$got" "$want" >&2
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

# Commit file $2 with content and message $3 in the repo at $1.
commit_file() {
	local repo="$1" name="$2" text="$3"
	printf '%s\n' "$text" >"$repo/$name"
	git -C "$repo" add "$name"
	git -C "$repo" -c commit.gpgsign=false commit -q -m "$text"
}

# Repo on main with one commit; prints the repo dir.
setup_repo() {
	local dir="$TMPDIR_ROOT/$1"
	mkdir -p "$dir"
	git -C "$dir" init -q --initial-branch=main
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
	git -C "$dir" branch plan/x
	raise_marker "$dir"
	printf '%s' "$dir"
}

# Repo on branch $2 with claude.protectMain enabled; prints the repo dir.
setup_protected_repo() {
	local dir
	dir=$(setup_repo "$1")
	git -C "$dir" branch -M "$2"
	git -C "$dir" config claude.protectMain true
	printf '%s' "$dir"
}

# Create branch $2 in the repo at $1 without switching to it.
add_branch() {
	git -C "$1" branch "$2"
}

# Work repo on trunk $2 (default main) with a local fix-ci/lint branch, wired
# to a local bare origin. Prints the work dir; the bare origin is always
# "<work>/../origin.git".
setup_pair() {
	local base="$TMPDIR_ROOT/$1" trunk="${2:-main}"
	local work="$base/work"
	mkdir -p "$base"
	git init -q --bare --initial-branch="$trunk" "$base/origin.git"
	git init -q --initial-branch="$trunk" "$work"
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

# ── Markers ──────────────────────────────────────────────────────────────────
# Both flows gate on a marker file in the git dir that marker_fresh
# judges by mtime; the two trios below differ only in the file name.

raise_marker() {
	touch "$(git -C "$1" rev-parse --absolute-git-dir)/fix-ci-active"
}

marker_path() {
	printf '%s/fix-ci-active' "$(git -C "$1" rev-parse --absolute-git-dir)"
}

# One minute past the marker's 30-minute freshness TTL, and 60 minutes ahead
# for clock-skew coverage (see branch-policy.sh's MARKER_TTL_SECONDS).
export STALE_OFFSET_MINUTES=-31
readonly STALE_OFFSET_MINUTES
export FUTURE_OFFSET_MINUTES=+60
readonly FUTURE_OFFSET_MINUTES

backdate_marker() {
	touch -t "$(date_offset_minutes "$2" +%Y%m%d%H%M)" "$(marker_path "$1")"
}

# The marker /release raises to sanction a run, in the repo at $1.
release_marker_path() {
	printf '%s/release-active' "$(git -C "$1" rev-parse --absolute-git-dir)"
}

raise_release_marker() {
	touch "$(release_marker_path "$1")"
}

# Move the release marker's mtime by $2 minutes, out of the shared freshness window.
backdate_release_marker() {
	touch -t "$(date_offset_minutes "$2" +%Y%m%d%H%M)" "$(release_marker_path "$1")"
}

# setup_pair "$1" with a fresh fix-ci marker raised immediately after; prints
# the work dir.
setup_marked_pair() {
	local work
	work=$(setup_pair "$1")
	raise_marker "$work"
	printf '%s' "$work"
}

# Clone $1's origin into a sibling "other" checkout, commit a foreign file on
# branch $2 there, and push it — advances the remote branch independently of
# the caller's own work tree.
advance_origin_branch() {
	local work="$1" branch="$2" other
	other="$(dirname "$work")/other"
	git clone -q "$(bare_of "$work")" "$other"
	init_git_identity "$other"
	git -C "$other" switch -q "$branch"
	commit_file "$other" THEIRS "theirs"
	git -C "$other" push -q origin "$branch"
}

advance_origin_main() {
	advance_origin_branch "$1" main
}
