# shellcheck shell=bash
#
# Policy for the branches the assistant owns, shared by the fix-ci push wrapper
# (scripts/fix-ci-push.sh), the plan squash script (scripts/merge-plan.sh), and
# the git guard hook (hooks/git-guard.sh). They gate on the same facts — is a
# fix-ci loop or a /merge-plan run live in this repo, and does this push delete
# anything outside the assistant's own branches — so the answers are defined
# once, here.
#
# What each caller does with an answer stays with the caller: the hook sweeps a
# dead marker and falls back to its normal blocks, the scripts exit 2 with a
# reason. So does each caller's own argv dialect — which spellings of --delete
# it recognises, which flags it lets through.
#
# Sourced, never executed: no `set -euo pipefail` here, since it would leak into
# whatever sourced it. Every caller sets it itself.

# `die` and portable stat access. Resolved from this file's own location, since
# the sourcing script may run from any cwd.
# shellcheck source=SCRIPTDIR/sh-common.sh
. "${BASH_SOURCE[0]%/*}/sh-common.sh"

# Marker files in the git dir. The fix-ci and merge-plan skills raise and drop
# them by these same names.
# shellcheck disable=SC2034 # read by the sourcing scripts and hook, not here
readonly FIX_CI_MARKER=fix-ci-active MERGE_PLAN_MARKER=merge-plan-active

# A live loop refreshes its marker's mtime each iteration, and /merge-plan raises
# its marker right before the run, so only a marker abandoned by an interrupted
# session ages out. Both markers share the window.
readonly MARKER_TTL_SECONDS=1800

# The branch a plan run works and ships on is plan/<slug>.
readonly PLAN_BRANCH_PREFIX=plan/

# Dies naming stat when marker_fresh's status $1 says no stat dialect answered;
# returns otherwise. Exit 1: a broken tool, not a refusal of the run.
die_if_stat_unusable() {
	(($1 != SH_STAT_UNUSABLE)) ||
		die "stat answers neither BSD nor GNU format flags; marker age cannot be read." 1
}

# Prints the absolute git dir of the repo the caller runs in, or dies. git's own
# stderr is left visible on purpose: a safe.directory refusal and a corrupt repo
# both surface as this failure and need telling apart. The caller's PROG names
# the refusal.
policy_git_dir() {
	command -v git >/dev/null || die "git is not installed."
	git rev-parse --absolute-git-dir || die "not inside a usable git repository."
}

# True when the marker at $1 proves a run is live right now. Only a regular file
# counts. The window is bounded on both sides: a marker aged past the TTL, dated
# ahead of now by a skewed clock or by hand, or whose mtime cannot be read proves
# nothing either way, and every one of those reads as absent (exit 1). A stat
# that answers no dialect at all exits SH_STAT_UNUSABLE instead: the marker may
# be perfectly live, so a caller must neither sweep it nor report it stale.
marker_fresh() {
	local marker="$1" mtime now status=0
	[[ -f "$marker" ]] || return 1
	mtime=$(sh_file_attr mtime "$marker") || status=$?
	((status == SH_STAT_UNUSABLE)) && return "$status"
	((status == 0)) || return 1
	now=$(date +%s)
	((now >= mtime && now - mtime <= MARKER_TTL_SECONDS))
}

# Refs a push actually deletes, one per line. Under --delete every refspec is a
# deletion; without it, only a leading-colon refspec such as ':main' deletes on
# its own. Recognising --delete is the caller's job — pass its verdict as $1.
push_deleted_refs() {
	local delete_mode="$1"
	shift
	local ref
	for ref in "$@"; do
		if [[ "$delete_mode" == true ]]; then
			printf '%s\n' "$ref"
		elif [[ "$ref" == :* ]]; then
			printf '%s\n' "${ref#:}"
		fi
	done
}

# True when a ref belongs to a namespace whose branches are the assistant's own
# and disposable — the only refs it may delete, locally or on a remote.
# `fix-ci/*` holds a CI-fix loop's throwaway branches; `plan/*` holds the branch
# a plan run works and ships on, which is squash-merged and then cleaned up.
ref_in_own_namespace() {
	local ref="${1#refs/heads/}"
	[[ "$ref" == fix-ci/* || "$ref" == "$PLAN_BRANCH_PREFIX"* ]]
}
