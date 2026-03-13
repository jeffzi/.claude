#!/usr/bin/env bash
set -euo pipefail

# ╭────────────────────────────────────────────────────────────╮
# │                  Worktree Safety Hook                      │
# ╰────────────────────────────────────────────────────────────╯
# Blocks ExitWorktree when the worktree has uncommitted changes.
# Prevents losing in-progress work after context compression.

# Skip if not in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Check for uncommitted changes (staged, unstaged, untracked)
dirty=false
git diff --quiet 2>/dev/null || dirty=true
git diff --cached --quiet 2>/dev/null || dirty=true
[[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]] && dirty=true

if $dirty; then
	printf "BLOCKED: Worktree has uncommitted changes. Commit your work before exiting.\n" >&2
	printf "Run 'git status' to see what needs to be committed.\n" >&2
	exit 2
fi

exit 0
