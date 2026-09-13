#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                  Worktree Safety Hook                      │
# ╰────────────────────────────────────────────────────────────╯
# Blocks ExitWorktree when the worktree has uncommitted changes.
# Prevents losing in-progress work after context compression.

# Resolved from the hook's own location: the hook runs with cwd set to the
# worktree it guards.
# shellcheck source=SCRIPTDIR/../scripts/sh-common.sh
. "${BASH_SOURCE[0]%/*}/../scripts/sh-common.sh"

git --no-optional-locks rev-parse --git-dir >/dev/null 2>&1 || exit 0

if sh_git_dirty . --untracked >/dev/null; then
	printf "BLOCKED: Worktree has uncommitted changes. Commit your work before exiting.\n" >&2
	printf "Run 'git status' to see what needs to be committed.\n" >&2
	exit 2
fi

exit 0
