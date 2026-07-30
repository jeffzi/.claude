# shellcheck shell=bash
#
# Policy shared by the fix-ci push wrapper (scripts/fix-ci-push.sh) and the git
# guard hook (hooks/git-guard.sh). Both gate on the same two facts — is a loop
# live in this repo, and does this push delete anything outside the loop's own
# branches — so the answers are defined once, here.
#
# What each caller does with an answer stays with the caller: the hook sweeps a
# dead marker and falls back to its normal blocks, the wrapper exits 2 with a
# reason. So does each caller's own argv dialect — which spellings of --delete
# it recognises, which flags it lets through.
#
# Sourced, never executed: no `set -euo pipefail` here, since it would leak into
# whatever sourced it. Both callers set it themselves.

# The running loop refreshes the marker's mtime each iteration, so only a marker
# abandoned by an interrupted session ages out.
readonly FIX_CI_MARKER_TTL_SECONDS=1800

# True when the marker proves a loop is live right now. The window is bounded on
# both sides: a marker aged past the TTL, dated ahead of now by a skewed clock or
# by hand, or whose mtime cannot be read at all proves nothing either way, and
# every one of those reads as absent.
#
# `stat -f %m` is BSD/macOS; both callers only ever run on Darwin.
fix_ci_marker_fresh() {
	local marker="$1" mtime now
	mtime=$(stat -f %m "$marker" 2>/dev/null) || return 1
	now=$(date +%s)
	((now >= mtime && now - mtime <= FIX_CI_MARKER_TTL_SECONDS))
}

# Refs a push actually deletes, one per line. Under --delete every refspec is a
# deletion; without it, only a leading-colon refspec such as ':main' deletes on
# its own. Recognising --delete is the caller's job — pass its verdict as $1.
fix_ci_deleted_refs() {
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

# True when a ref belongs to the loop's own throwaway namespace — the only refs
# it may delete, locally or on a remote.
fix_ci_ref_in_namespace() {
	[[ "${1#refs/heads/}" == fix-ci/* ]]
}
