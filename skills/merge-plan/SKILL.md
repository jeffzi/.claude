---
name: merge-plan
description: >
  Use when the user invokes /merge-plan to land a finished plan branch on its base branch as one squash
  commit — after execute-plan's Ship section names it, or "merge the plan", "squash the plan
  branch". Not for feature branches or CI fixes — use fix-ci. Never for the assistant's own use.
argument-hint: "[--force]"
disable-model-invocation: true
allowed-tools:
  - Bash(~/.claude/scripts/merge-plan.sh *)
  - Bash(touch *merge-plan-active)
  - Bash(rm -f *merge-plan-active)
  - Bash(git branch --show-current*)
  - Bash(git log *)
  - Bash(git rev-parse *)
  - Bash(git status *)
  - Bash(~/.claude/scripts/plan-branch.sh base*)
  - Bash(git diff *)
  - Bash(mkdir -p *plan-squash)
  - Bash(ls *)
  - Read
  - Write
---

# Merge Plan

**Arguments:** $ARGUMENTS

Squash-merge the current `plan/<slug>` branch onto its recorded base (`main` by default, the branch
it was created from otherwise), push, delete the branch. The script does every git write; this skill
only raises the marker that lets it run, runs it once, and reports what it said.

## Context

- Branch: !`git branch --show-current 2>/dev/null || true`
- Squash message: !`ls "$(git rev-parse --absolute-git-dir 2>/dev/null)/plan-squash/" 2>/dev/null ||
  echo "(none)"`

## The one path

Three **separate** Bash calls, in this order. The guard inspects each call before it runs, so the
marker must already exist on disk when the script call reaches it — one combined call is blocked.

```bash
git_dir=$(git rev-parse --absolute-git-dir) && touch "$git_dir/merge-plan-active"   # call 1
~/.claude/scripts/merge-plan.sh $ARGUMENTS                                          # call 2
rm -f "$(git rev-parse --absolute-git-dir)/merge-plan-active"                       # call 3 — ALWAYS
```

Off a `plan/*` branch (Context shows another branch): report the branch and stop. No marker.

The script refuses, with a reason, when the tree is dirty, the squash message file is missing, the
base is behind its `origin/` counterpart, the branch has no recorded base or it no longer exists, or
the branch tip's CI run is not green. `--force` passes through to it and bypasses only the CI gate.

## `--force`

The user's word for "merge what is on the branch". It does two things and nothing else:

1. **CI gate off.** The script skips the CI check; every other refusal still stands.
2. **Missing message written.** When Context shows `(none)` for the squash message, write it before
   call 1: load `Skill(write-commit)`, compose one conventional message for the whole branch from
   the plan's **Goal** in `.planning/` and `git diff <base>...HEAD --stat` (`<base>` is what
   `~/.claude/scripts/plan-branch.sh base` prints), `mkdir -p "$git_dir/plan-squash"`, and Write it
   to `$git_dir/plan-squash/<slug>.msg`. No plan slug, no `.planning/` path, no process words in the
   message. A message that already exists is never rewritten.

Without `--force` a missing message is a refusal to report, exactly as the script says.

## Report

One line on success: the base branch, its new commit (`git log -1 --oneline <base>`), and that the
plan branch is gone. On refusal: the script's reason verbatim, and stop. Nothing else.

## Bright lines

- **One run.** A refusal is the answer, not a retry prompt. Never fix the tree, rewrite the message
  file, or re-run with `--force` on your own initiative — the user reads the reason and decides.
- **No git writes here.** No `git commit`, `merge`, `push`, `branch -D`, `switch` — the script owns
  them. This skill's own git use is the read-only Context above.
- **The marker lives only inside the block above.** Touched immediately before the script, removed
  immediately after, on every exit path. It is never raised outside this skill — not by
  `execute-plan`, not by a "quick manual merge".

| Excuse                                               | Reality                                                      |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| "CI is just slow — skip it this once"                | `--force` is the user's word, passed in. Never added.        |
| "The message file is missing, I'll write one"        | Only under `--force`. Otherwise missing → report.            |
| "`--force` means merge no matter what"               | CI and the message only. Dirty tree, stale base → refusal.   |
| "The tree is dirty with one obvious file, commit it" | Refusal. The user decides what that file is.                 |
| "The refusal is a precondition, fix it and re-run"   | One run. Report the reason; the next run is the user's call. |
| "Leave the marker, the user might merge again"       | A lingering marker lets the script run outside this skill.   |
