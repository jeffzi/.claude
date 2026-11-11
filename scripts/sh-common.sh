# shellcheck shell=bash
#
# Helpers every script and hook in this tree can share: a refusal exit, a
# hook-payload field reader, a dirty-worktree probe, portable `stat` access, and
# the shared EXIT trap behind `sh_remove_on_exit` and `sh_fail_closed`.
# Sourced, never executed: no `set -euo pipefail` here, since it would leak
# into whatever sourced it.
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

# The one wording for a stat that answers neither dialect. A caller appends what
# it could not read: `die "$SH_STAT_UNUSABLE_MSG; marker age cannot be read." 1`.
# shellcheck disable=SC2034 # read by the sourcing scripts
readonly SH_STAT_UNUSABLE_MSG="stat answers neither BSD (-f) nor GNU (-c) format flags"

# Prints "<program>: <message>" on stderr and exits with $2 — default 2, the
# refusal that changed nothing. Each script sets PROG after sourcing; one that
# never did is named by its own basename.
die() {
	printf '%s: %s\n' "${PROG:-${0##*/}}" "$1" >&2
	exit "${2:-2}"
}

# Files sh_exit_handler removes, and whether it fails closed; see
# sh_remove_on_exit and sh_fail_closed.
SH_EXIT_REMOVE=()
SH_FAIL_CLOSED=""

# The single EXIT trap behind sh_remove_on_exit and sh_fail_closed, so the two
# compose instead of one `trap … EXIT` replacing the other. Removes every
# registered file, then — when the script opted in with sh_fail_closed — turns
# any exit status other than 0 (allow) and 2 (block) into a refusal naming that
# status. Returning without `exit` keeps the original status.
sh_exit_handler() {
	local status=$?
	((${#SH_EXIT_REMOVE[@]} == 0)) || rm -f "${SH_EXIT_REMOVE[@]}"
	[[ -n "$SH_FAIL_CLOSED" ]] || return 0
	((status == 0 || status == 2)) || die "unexpected exit $status; failing closed"
}

# Removes file $1 when the shell exits, however it exits. Installs the shared
# EXIT trap, so a script that sets its own EXIT trap must not call this.
sh_remove_on_exit() {
	SH_EXIT_REMOVE+=("$1")
	trap sh_exit_handler EXIT
}

# Opts a hook into failing closed: Claude Code reads only exit 2 as a block, so
# an unexpected failure — a `set -e` abort, a missing tool exiting 127 — would
# otherwise let the guarded call through. Every exit other than 0 and 2 becomes
# exit 2 naming the hook and the original status.
#
# An EXIT trap, never `set -E` with an ERR trap: under bash 3.2 an ERR trap also
# fires inside a command substitution such as `$(ils parse …)`, turning its
# expected exit 1 into a refusal. Scripts whose exit 1 means a broken tool, not
# a refusal, must not opt in.
sh_fail_closed() {
	SH_FAIL_CLOSED=1
	trap sh_exit_handler EXIT
}

# Prints the result of jq filter $2 applied to the JSON document $1, such as a
# field of a hook payload. Dies (exit 2) when jq is missing: Claude Code treats
# only exit 2 as a block, and a hook that cannot read its payload cannot vouch
# for the call it guards.
sh_input_field() {
	command -v jq >/dev/null || die "jq is required to read the hook payload"
	printf '%s' "$1" | jq -r "$2"
}

# True when the worktree at $1 has uncommitted changes; prints which part is
# dirty first: `unstaged`, `staged`, or — only with `--untracked` as $2 —
# `untracked`. A git that cannot answer reads as dirty, so a guard asking before
# a destructive step fails closed. `--no-optional-locks` keeps the probe from
# taking index.lock out from under a git command running beside it.
sh_git_dirty() {
	local dir="$1" untracked="${2:-}"
	local -a git_cmd=(git --no-optional-locks -C "$dir")
	if ! "${git_cmd[@]}" diff --quiet 2>/dev/null; then
		printf 'unstaged'
	elif ! "${git_cmd[@]}" diff --cached --quiet 2>/dev/null; then
		printf 'staged'
	elif [[ "$untracked" == --untracked &&
		-n "$("${git_cmd[@]}" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
		printf 'untracked'
	else
		return 1
	fi
}

# BSD stat takes `-f <fmt>` and GNU stat `-c <fmt>`, and the attribute letters
# differ too. The dialect is probed once at source time against this file, which
# is guaranteed to exist, since callers stat inside loops. Each format is an
# array — flag, then value — so the two reach stat apart whatever IFS the caller
# runs under; both are empty when neither dialect answers. A function, so a test
# can probe again under a stubbed PATH without sourcing this file twice.
sh_detect_stat() {
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
}

sh_detect_stat

# True when a `stat` dialect answered at source time, so sh_file_attr can read
# attributes at all.
sh_stat_usable() {
	((${#SH_STAT_MTIME_FMT[@]}))
}

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
