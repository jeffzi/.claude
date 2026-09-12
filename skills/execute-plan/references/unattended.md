# Unattended Marker

## What it is

A file at `$(git rev-parse --absolute-git-dir)/execute-plan-unattended` containing this session's
id. The collab-reminder hook honors it for this session only and injects the unattended policy line
on every turn; the `tdd` SURFACE gate and the CLAUDE.md surface rule key off that injected line.

Removing the marker is cleanup of a file this workflow created, not a destructive operation.

## Commands

Capture `git_dir` first so a failed `rev-parse` is loud, not silent:

```bash
git_dir=$(git rev-parse --absolute-git-dir)
# Raise (before Task 1):
printf '%s\n' "${CLAUDE_SESSION_ID}" >"$git_dir/execute-plan-unattended"
# Remove (final or halt report):
rm "$git_dir/execute-plan-unattended"
```
