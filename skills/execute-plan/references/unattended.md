# Unattended Marker

## What it is

A file at `$(git rev-parse --absolute-git-dir)/execute-plan-unattended` containing this session's
id. The `tdd` SURFACE gate and the CLAUDE.md surface rule key off it: a marker holding this
session's id means the run is unattended, and a marker holding any other id — one an interrupted
plan left behind — means nothing.

Removing the marker is cleanup of a file this workflow created, not a destructive operation.

## Commands

Capture `git_dir` first so a failed `rev-parse` is loud, not silent. The session id comes from the
shell environment as `CLAUDE_CODE_SESSION_ID` — the `${CLAUDE_SESSION_ID}` substitution only runs
over a SKILL.md body, never over this reference file — and the `:?` expansion fails the raise when
that variable is unset instead of writing a blank marker no session would match:

```bash
git_dir=$(git rev-parse --absolute-git-dir)
# Raise (before Task 1):
printf '%s\n' "${CLAUDE_CODE_SESSION_ID:?session id not exported}" >"$git_dir/execute-plan-unattended"
# Remove (final or halt report):
rm "$git_dir/execute-plan-unattended"
```
