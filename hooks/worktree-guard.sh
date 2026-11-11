#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                  Worktree Safety Hook                      │
# ╰────────────────────────────────────────────────────────────╯
# Blocks ExitWorktree when the worktree has uncommitted changes.
# Prevents losing in-progress work after context compression.

# Resolved from the hook's own location: the hook runs with cwd set to the
# worktree it guards.
# `bash hook.sh` run from inside hooks/ leaves no slash to strip a directory at.
HOOK_SOURCE=${BASH_SOURCE[0]}
[[ "$HOOK_SOURCE" == */* ]] || HOOK_SOURCE="./$HOOK_SOURCE"
HOOK_DIR=$(cd "${HOOK_SOURCE%/*}" && pwd)
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "$HOOK_DIR/../scripts/sh-common.sh"
PROG=worktree-guard
sh_fail_closed

main() {
	git --no-optional-locks rev-parse --git-dir >/dev/null 2>&1 || exit 0

	if sh_git_dirty . --untracked >/dev/null; then
		die "BLOCKED: Worktree has uncommitted changes. Commit your work before exiting.
Run 'git status' to see what needs to be committed."
	fi

	exit 0
}

main "$@"
