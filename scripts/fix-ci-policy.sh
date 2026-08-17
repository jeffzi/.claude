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

# BSD stat uses `-f %m`, GNU stat uses `-c %Y`. Probe once at source-time against
# a file guaranteed to exist (this script itself). Callers run on both Darwin
# (local) and Linux (CI).
_detect_stat_fmt() {
	if stat -f %m "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
		printf -- '-f %%m'
	elif stat -c %Y "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
		printf -- '-c %%Y'
	fi
}
_FIX_CI_STAT_FMT=$(_detect_stat_fmt)

# True when the marker proves a loop is live right now. The window is bounded on
# both sides: a marker aged past the TTL, dated ahead of now by a skewed clock or
# by hand, or whose mtime cannot be read at all proves nothing either way, and
# every one of those reads as absent.
fix_ci_marker_fresh() {
	local marker="$1" mtime now
	[[ -n "$_FIX_CI_STAT_FMT" ]] || return 1
	# shellcheck disable=SC2086 # _FIX_CI_STAT_FMT must word-split into two arguments
	mtime=$(stat $_FIX_CI_STAT_FMT "$marker" 2>/dev/null) || return 1
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
