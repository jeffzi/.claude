#!/usr/bin/env bash
set -euo pipefail

WRAPPER="$HOME/.claude/scripts/fix-ci-push.sh"
BASH_BIN=$(command -v bash)
PASS=0
FAIL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

# Run the wrapper from inside $1 with the remaining args, capture exit + stderr
run_wrapper() {
	local dir="$1"
	shift
	local exit_code=0
	local stderr_out
	stderr_out=$(cd "$dir" && "$WRAPPER" "$@" 2>&1 1>/dev/null) || exit_code=$?
	printf '%d\t%s' "$exit_code" "$stderr_out"
}

expect_refused() {
	local desc="$1"
	local dir="$2"
	shift 2
	local result exit_code stderr
	result=$(run_wrapper "$dir" "$@")
	exit_code="${result%%	*}"
	stderr="${result#*	}"
	if [[ "$exit_code" -eq 2 && -n "$stderr" ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (exit %d, expected 2 with a stderr reason)\n    stderr: %s\n" \
			"$desc" "$exit_code" "$stderr"
		((++FAIL))
	fi
}

expect_pushed() {
	local desc="$1"
	local dir="$2"
	shift 2
	local result exit_code stderr
	result=$(run_wrapper "$dir" "$@")
	exit_code="${result%%	*}"
	if [[ "$exit_code" -eq 0 ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		stderr="${result#*	}"
		printf "FAIL  %s  (exit %d, expected 0)\n    stderr: %s\n" "$desc" "$exit_code" "$stderr"
		((++FAIL))
	fi
}

# Non-zero without pinning the code: a refusal (2) and a rejection propagated
# from git (1) are both acceptable outcomes for a push that must not land
expect_failed() {
	local desc="$1"
	local dir="$2"
	shift 2
	local result exit_code stderr
	result=$(run_wrapper "$dir" "$@")
	exit_code="${result%%	*}"
	if [[ "$exit_code" -ne 0 ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		stderr="${result#*	}"
		printf "FAIL  %s  (exit 0, expected non-zero)\n    stderr: %s\n" "$desc" "$stderr"
		((++FAIL))
	fi
}

expect_reason() {
	local desc="$1"
	local dir="$2"
	local pattern="$3"
	shift 3
	local result exit_code stderr
	result=$(run_wrapper "$dir" "$@")
	exit_code="${result%%	*}"
	stderr="${result#*	}"
	if [[ "$exit_code" -ne 0 && "$stderr" == *"$pattern"* ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (exit %s, stderr missing %s)\n    stderr: %s\n" \
			"$desc" "$exit_code" "$pattern" "$stderr"
		((++FAIL))
	fi
}

# PATH is emptied for the callee only, so the interpreter has to be named
# explicitly — `#!/usr/bin/env bash` would resolve against the empty PATH too
expect_reason_without_git() {
	local desc="$1"
	local pattern="$2"
	shift 2
	local exit_code=0
	local stderr
	stderr=$(env PATH=/var/empty "$BASH_BIN" "$WRAPPER" "$@" 2>&1 1>/dev/null) || exit_code=$?
	if [[ "$exit_code" -ne 0 && "$stderr" == *"$pattern"* ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (exit %s, stderr missing %s)\n    stderr: %s\n" \
			"$desc" "$exit_code" "$pattern" "$stderr"
		((++FAIL))
	fi
}

expect_ref_at() {
	local desc="$1"
	local bare="$2"
	local ref="$3"
	local want="$4"
	local got
	got=$(git -C "$bare" rev-parse "refs/heads/$ref" 2>/dev/null) || got="<missing>"
	if [[ "$got" == "$want" ]]; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (refs/heads/%s is %s, expected %s)\n" "$desc" "$ref" "$got" "$want"
		((++FAIL))
	fi
}

expect_ref_present() {
	local desc="$1"
	local bare="$2"
	local ref="$3"
	if git -C "$bare" show-ref --quiet --verify "refs/heads/$ref"; then
		printf "PASS  %s\n" "$desc"
		((++PASS))
	else
		printf "FAIL  %s  (refs/heads/%s missing from %s)\n" "$desc" "$ref" "$bare"
		((++FAIL))
	fi
}

expect_ref_absent() {
	local desc="$1"
	local bare="$2"
	local ref="$3"
	if git -C "$bare" show-ref --quiet --verify "refs/heads/$ref"; then
		printf "FAIL  %s  (refs/heads/%s present in %s)\n" "$desc" "$ref" "$bare"
		((++FAIL))
	else
		printf "PASS  %s\n" "$desc"
		((++PASS))
	fi
}

# ── Fixtures ──────────────────────────────────────────────────────────────────

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Work repo on main with a local fix-ci/lint branch, wired to a local bare origin.
# Prints the work dir; the bare origin is always "<work>/../origin.git".
setup_pair() {
	local base="$TMPDIR_ROOT/$1"
	local work="$base/work"
	mkdir -p "$base"
	git init -q --bare --initial-branch=main "$base/origin.git"
	git init -q --initial-branch=main "$work"
	git -C "$work" config user.email "test@test.com"
	git -C "$work" config user.name "Test"
	touch "$work/README"
	git -C "$work" add README
	git -C "$work" -c commit.gpgsign=false commit -q -m "init"
	git -C "$work" branch fix-ci/lint
	git -C "$work" remote add origin "$base/origin.git"
	printf '%s' "$work"
}

bare_of() {
	printf '%s' "${1%/work}/origin.git"
}

# Seed the bare origin without going through the wrapper under test
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

NO_MARKER=$(setup_pair no_marker)

STALE=$(setup_pair stale)
raise_marker "$STALE"
touch -t "$(date -v-31M +%Y%m%d%H%M)" \
	"$(git -C "$STALE" rev-parse --absolute-git-dir)/fix-ci-active"

# Clock skew or a forged mtime must not buy an unbounded window: freshness is
# bounded on both sides, so a marker dated ahead of now reads as absent
FUTURE=$(setup_pair future)
raise_marker "$FUTURE"
touch -t "$(date -v+60M +%Y%m%d%H%M)" \
	"$(git -C "$FUTURE" rev-parse --absolute-git-dir)/fix-ci-active"

PLAIN=$(setup_pair plain)
raise_marker "$PLAIN"

UPSTREAM=$(setup_pair upstream)
raise_marker "$UPSTREAM"

# All refusals share one repo: a refused push leaves the origin untouched
REFUSE=$(setup_pair refuse)
raise_marker "$REFUSE"
seed_origin "$REFUSE" main

DELETE_FLAG=$(setup_pair delete_flag)
raise_marker "$DELETE_FLAG"
seed_origin "$DELETE_FLAG" main fix-ci/lint

DELETE_COLON=$(setup_pair delete_colon)
raise_marker "$DELETE_COLON"
seed_origin "$DELETE_COLON" main fix-ci/lint

# Origin whose main has moved on independently, plus a repo-local push refspec
# that would force-update every branch. The argv the wrapper sees is clean, so
# the config is the only thing that could turn a plain push into a rewrite.
FORCE_CONFIG=$(setup_pair force_config)
raise_marker "$FORCE_CONFIG"
seed_origin "$FORCE_CONFIG" main
FORCE_CONFIG_BARE=$(bare_of "$FORCE_CONFIG")
FORCE_CONFIG_OTHER="$TMPDIR_ROOT/force_config/other"
git clone -q "$FORCE_CONFIG_BARE" "$FORCE_CONFIG_OTHER"
git -C "$FORCE_CONFIG_OTHER" config user.email "other@test.com"
git -C "$FORCE_CONFIG_OTHER" config user.name "Other"
touch "$FORCE_CONFIG_OTHER/THEIRS"
git -C "$FORCE_CONFIG_OTHER" add THEIRS
git -C "$FORCE_CONFIG_OTHER" -c commit.gpgsign=false commit -q -m "theirs"
git -C "$FORCE_CONFIG_OTHER" push -q origin main
FORCE_CONFIG_HEAD=$(git -C "$FORCE_CONFIG_BARE" rev-parse refs/heads/main)
touch "$FORCE_CONFIG/MINE"
git -C "$FORCE_CONFIG" add MINE
git -C "$FORCE_CONFIG" -c commit.gpgsign=false commit -q -m "mine"
git -C "$FORCE_CONFIG" config remote.origin.push '+refs/heads/*:refs/heads/*'

NOT_A_REPO="$TMPDIR_ROOT/not_a_repo"
mkdir -p "$NOT_A_REPO"

# ── Tests ─────────────────────────────────────────────────────────────────────

printf "\n── Marker gate ──────────────────────────────────────────────────────────────\n"
expect_refused "push without a marker" "$NO_MARKER" origin fix-ci/lint
expect_ref_absent "nothing pushed without a marker" "$(bare_of "$NO_MARKER")" fix-ci/lint
expect_refused "push under a marker older than the TTL" "$STALE" origin fix-ci/lint
expect_ref_absent "nothing pushed under a stale marker" "$(bare_of "$STALE")" fix-ci/lint
expect_refused "push under a marker dated in the future" "$FUTURE" origin fix-ci/lint
expect_ref_absent "nothing pushed under a future-dated marker" "$(bare_of "$FUTURE")" fix-ci/lint

printf "\n── Pass-through under a fresh marker ────────────────────────────────────────\n"
expect_pushed "push of a fix-ci branch" "$PLAIN" origin fix-ci/lint
expect_ref_present "fix-ci branch landed in origin" "$(bare_of "$PLAIN")" fix-ci/lint
expect_pushed "push -u of a fix-ci branch" "$UPSTREAM" -u origin fix-ci/lint
expect_ref_present "-u branch landed in origin" "$(bare_of "$UPSTREAM")" fix-ci/lint

printf "\n── Flag whitelist (every force form) ────────────────────────────────────────\n"
expect_refused "push -f" "$REFUSE" -f origin fix-ci/lint
expect_refused "push --force-with-lease" "$REFUSE" --force-with-lease origin fix-ci/lint
expect_refused "push -fu (bundled force)" "$REFUSE" -fu origin fix-ci/lint
expect_refused "push --mirror" "$REFUSE" --mirror origin
expect_refused "push +main:main (force refspec)" "$REFUSE" origin +main:main

printf "\n── Delete scoping ───────────────────────────────────────────────────────────\n"
expect_refused "push --delete main" "$REFUSE" origin --delete main
expect_refused "push :main (delete refspec)" "$REFUSE" origin :main
expect_ref_present "origin main survived every refusal" "$(bare_of "$REFUSE")" main
expect_ref_absent "no branch leaked into origin from a refusal" "$(bare_of "$REFUSE")" fix-ci/lint
expect_pushed "push --delete fix-ci/lint" "$DELETE_FLAG" origin --delete fix-ci/lint
expect_ref_absent "fix-ci branch deleted from origin" "$(bare_of "$DELETE_FLAG")" fix-ci/lint
expect_pushed "push :fix-ci/lint (delete refspec)" "$DELETE_COLON" origin :fix-ci/lint
expect_ref_absent "colon-deleted fix-ci branch gone from origin" "$(bare_of "$DELETE_COLON")" fix-ci/lint

printf "\n── Repo config cannot inject a force ────────────────────────────────────────\n"
expect_failed "push under a force-everything push refspec" "$FORCE_CONFIG" origin
expect_ref_at "diverged origin main survived the config force" \
	"$FORCE_CONFIG_BARE" main "$FORCE_CONFIG_HEAD"

printf "\n── Diagnostics ──────────────────────────────────────────────────────────────\n"
expect_reason "git's own reason for an unusable repo" "$NOT_A_REPO" \
	"not a git repository" origin fix-ci/lint
expect_reason_without_git "missing git named as the cause" \
	"git is not installed" origin fix-ci/lint

printf "\n─────────────────────────────────────────────────────────────────────────────\n"
printf "%d passed, %d failed\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
