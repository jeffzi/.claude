# shellcheck shell=bash
#
# Helpers every script and hook in this tree can share: a refusal exit and
# portable `stat` access. Sourced, never executed: no `set -euo pipefail` here,
# since it would leak into whatever sourced it.
#
# Sourced through more than one path in one shell (a hook that loads a policy
# library which loads this) — the sentinel makes the second load a no-op, which
# is also what keeps the `readonly` below from tripping.
[[ -n "${SH_COMMON_SOURCED:-}" ]] && return 0
SH_COMMON_SOURCED=1

# Exit status of sh_file_attr when no `stat` dialect works at all. Distinct from
# a plain 1 (the path cannot be read) so a caller can tell a broken tool from a
# file that is simply not there.
readonly SH_STAT_UNUSABLE=3

# Prints "<program>: <message>" on stderr and exits with $2 — default 2, the
# refusal that changed nothing. Each script sets PROG after sourcing; one that
# never did is named by its own basename.
die() {
	printf '%s: %s\n' "${PROG:-${0##*/}}" "$1" >&2
	exit "${2:-2}"
}

# True when the worktree at $1 has uncommitted changes; prints which part is
# dirty first: `unstaged`, `staged`, or — only with `--untracked` as $2 —
# `untracked`. A git that cannot answer reads as dirty, so a guard asking before
# a destructive step fails closed. `--no-optional-locks` keeps the probe from
# taking index.lock out from under a git command running beside it.
sh_git_dirty() {
	local dir="$1" untracked="${2:-}"
	if ! git --no-optional-locks -C "$dir" diff --quiet 2>/dev/null; then
		printf 'unstaged'
	elif ! git --no-optional-locks -C "$dir" diff --cached --quiet 2>/dev/null; then
		printf 'staged'
	elif [[ "$untracked" == --untracked &&
		-n "$(git --no-optional-locks -C "$dir" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
		printf 'untracked'
	else
		return 1
	fi
}

# BSD stat takes `-f <fmt>` and GNU stat `-c <fmt>`, and the attribute letters
# differ too. The dialect is probed once at source time against this file, which
# is guaranteed to exist, since callers stat inside loops. Each format is an
# array — flag, then value — so the two reach stat apart whatever IFS the caller
# runs under; both are empty when neither dialect answers.
if stat -f %m "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
	SH_STAT_MTIME_FMT=(-f %m)
	SH_STAT_SIZE_FMT=(-f %z)
elif stat -c %Y "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
	SH_STAT_MTIME_FMT=(-c %Y)
	SH_STAT_SIZE_FMT=(-c %s)
else
	SH_STAT_MTIME_FMT=()
	SH_STAT_SIZE_FMT=()
fi

# Prints the mtime (epoch seconds) or size (bytes) of $2. Exit 1 when the path
# cannot be read, SH_STAT_UNUSABLE when no stat dialect works.
sh_file_attr() {
	local attr="$1" path="$2"
	case "$attr" in
	mtime)
		((${#SH_STAT_MTIME_FMT[@]})) || return "$SH_STAT_UNUSABLE"
		stat "${SH_STAT_MTIME_FMT[@]}" "$path" 2>/dev/null
		;;
	size)
		((${#SH_STAT_SIZE_FMT[@]})) || return "$SH_STAT_UNUSABLE"
		stat "${SH_STAT_SIZE_FMT[@]}" "$path" 2>/dev/null
		;;
	*) return 1 ;;
	esac
}
