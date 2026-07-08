# No Cross-Repository Edits Without Explicit Permission

Never edit, create, or delete files in a repository other than the one you were launched in. Always
ask the user first and explain what you found and why the other repo needs to change.

## What this covers

- **Write / Edit / NotebookEdit tools** targeting a path outside the session's git root.
- **Bash commands** that write files into another repo: `cp`, `mv`, `sed -i`, shell redirects (`>`),
  or any other write operation targeting a path in a different repository.
- **Git commands** run with `-C /other/repo` or after `cd /other/repo` that mutate that repo's index
  or working tree (commits, staging, restores).

## What "outside the session" means

The session's boundary is the git root of the directory where Claude Code was launched — the output
of `git rev-parse --show-toplevel` from the working directory. Any path that does not start with
that root is outside, regardless of whether it is:

- A sibling repository (`../other-project/`)
- A dependency or vendored copy
- A symlinked path that resolves outside the root

Worktrees of the same repository (`.claude/worktrees/…`) are inside the boundary.

## What "explicit permission" looks like

The user must say something equivalent to:

> "Go ahead and fix that in `tstl-optimize` too." "You can modify `../shared-lib/src/…` directly."

A general instruction to fix a bug does not grant permission to touch other repos. Inferring
permission from context ("the bug is clearly there and the user wants it fixed") is not permission.

## How to handle a cross-repo finding

1. Stop before touching the other repo.
2. Describe the finding: what file, what line, what change is needed and why.
3. Ask the user explicitly: "Do you want me to make this change in `tstl-optimize`? If so, open a
   separate session there or tell me to proceed."
4. Wait for a clear yes before acting.

## Rationalizations that are not permission

| Excuse                                   | Reality                                  |
| ---------------------------------------- | ---------------------------------------- |
| "The bug is obviously in the other repo" | Describe it; don't fix it unilaterally.  |
| "The user's goal requires this change"   | Ask. Goals don't grant cross-repo scope. |
| "It's a one-line fix, not a big deal"    | Scope, not size, is what matters.        |
| "I already found the root cause"         | Finding ≠ permission to fix.             |
| "The two repos are tightly coupled"      | Still two repos. Still need permission.  |
| "I'll mention it afterward"              | After is too late. Ask before.           |
