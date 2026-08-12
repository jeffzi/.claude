---
name: autocommit
description: Use when the user grants standing commit approval for the session — "auto-commit from now on", "commit as you go", "stop asking before commits". Grants committing verified work only — not pushes, not edits beyond what was requested.
allowed-tools:
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git tag *)
  - Bash(git status *)
  - Bash(git diff *)
  - Bash(git log *)
---

# Autocommit Mode

Standing approval to commit verified, requested work for the rest of the session — no per-commit
confirmation. Stay in this mode until the user says to exit.

**On activation, immediately:**

1. **Signing warm-up** — when `git config commit.gpgsign` is true, trigger one signature now, while
   the user is still at the keyboard to approve it, so later unattended commits reuse the
   authorization:

   ```bash
   git tag -s autocommit-warmup -m warmup && git tag -d autocommit-warmup
   ```

2. Confirm the mode is on in one line, including what it does NOT cover (pushes, unrequested edits).

## The grant

When a requested task's edits pass full verification, commit without asking. Load
`Skill(write-commit)` for message composition and granularity rules; **this mode pre-satisfies the
approval gate in its `references/interactive-flow.md`** — skip the AskUserQuestion confirmation,
never block a commit on it.

## Bright lines — the grant changes nothing else

- **Verification gate unchanged.** Implement → verify → commit; one failing check means no commit. A
  red test plus an away user means the work waits in the tree — never "commit with the failure
  noted".
- **Stage by explicit path** — only files this task touched. Never `git add -A` / `git add .`, never
  sweep the user's pre-existing dirty files or plan artifacts into a commit.
- **Commits only.** No push, no amend, no history rewriting — git-guard stays authoritative, and
  this mode is never cited as push permission.
- **Not scope license.** Read-only asks stay read-only; `no-unrequested-edits.md` still governs what
  may be edited. This mode governs committing requested work, nothing more.
- One commit per task (`write-commit` granularity), conventional message, no "wip" commits.

## Rationalizations

| Excuse                                          | Reality                                                      |
| ----------------------------------------------- | ------------------------------------------------------------ |
| "They authorized commits — a red test can ride" | The grant covers verified work. Red means hold.              |
| "Everything dirty may as well go in"            | Pre-existing edits are the user's. Stage your task's paths.  |
| "Auto-commit implies auto-push"                 | It doesn't. Push has its own rules and guard.                |
| "I fixed it during the review, so commit it"    | A review is read-only. Unrequested edits are never swept in. |

## How to exit

The user says "exit autocommit" (or equivalent). Also over when the session ends — the grant never
carries into a new session.
