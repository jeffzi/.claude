---
name: plan-commit
description: >
  Use when you have uncommitted changes and want to plan and execute granular, logical commits
  before pushing. Not for a single obvious commit — use write-commit directly.
argument-hint: "[path ...] [--exclude path ...]"
model: haiku
disable-model-invocation: true
effort: medium
---

# Plan Commits

## Arguments

Parse `ARGUMENTS` (injected at the bottom) before doing anything else.

- **Positional paths** — any token not starting with `--`: restrict scope to only these
  files/directories.
- **`--exclude <path>`** — repeatable: remove matching files from scope.

Build two lists from the parsed arguments:

- **INCLUDE** — explicit paths (empty = all changed files are in scope)
- **EXCLUDE** — paths to remove from scope (empty = nothing excluded)

Examples:

| Invocation                                   | Effect                           |
| -------------------------------------------- | -------------------------------- |
| `/plan-commit`                               | all changed files                |
| `/plan-commit skills/`                       | only files under `skills/`       |
| `/plan-commit --exclude settings.json`       | all files except `settings.json` |
| `/plan-commit skills/ --exclude skills/foo/` | `skills/` minus `skills/foo/`    |

Apply the filter immediately: for the rest of this skill, **in-scope files** means the changed files
that pass the INCLUDE/EXCLUDE rules. Silently ignore out-of-scope files — do not mention them in the
plan or commit them.

## Context

- All changes (staged, unstaged, untracked): !`git status --porcelain 2>/dev/null`
- Current git diff (staged and unstaged): !`git diff HEAD 2>/dev/null`
- Recent commits (for style reference): !`git log --oneline -10 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`

## Your task

Analyze all **in-scope** uncommitted changes and organize them into a plan of **granular, logical
commits** — each capturing one coherent unit of work.

If there are no in-scope uncommitted changes after applying the filter, inform the user and stop.

### Step 1: Load the write-commit skill

Invoke `Skill(write-commit)` to load commit message guidelines before proceeding.

### Step 2: Analyze and group changes

Read the diffs and untracked files. **Only consider in-scope files** (per the INCLUDE/EXCLUDE filter
resolved in the Arguments section). Group them by logical purpose:

- Changes that serve the same goal belong together (e.g. a function + its test + its import).
- Unrelated changes should be separate commits (e.g. a bug fix and a new feature).
- Prefer fewer, meaningful commits over many trivial ones. Don't split just to split.
- Respect file boundaries only when they align with purpose boundaries.
- Partial staging (`git add -p`) is not available. If a file contains changes for multiple commits,
  include it in the most relevant commit and note the constraint to the user.

### Step 3: Present the commit plan

Output a numbered plan. For each proposed commit:

1. **Subject line** — following write-commit guidelines (under 50 chars, impact-focused).
2. **Body** (optional) — only if the subject alone doesn't tell the full story.
3. **Files** — list the files that would be staged for this commit.

Format:

```markdown
## Commit Plan

### 1. <subject line>

<optional body>

Files:

- path/to/file1.py
- path/to/file2.py

### 2. <subject line>

...
```

### Step 4: Wait for approval

After presenting the plan, use **AskUserQuestion** to let the user confirm before executing.
Options:

- **Accept** — execute all commits in order.
- **Edit** — the user describes what to change (regroup files, reword messages, merge/split commits)
  and you revise the plan before executing.
- **Cancel** — do nothing.

### Step 5: Execute (only after approval)

For each commit in the approved plan, stage only the listed files and commit. Use `write-commit`
guidelines for the final message. Execute commits sequentially — each must succeed before the next.
If a commit fails, stop immediately and report the error. Do not continue with remaining commits.

**Do not push.** The user will push when ready.

## Common Mistakes

| Mistake                                                             | Fix                                                                         |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| A file appears in multiple commits because it changed incrementally | Include it in the most relevant commit and note the constraint to the user  |
| Over-splitting one logical change into many trivial commits         | Group by purpose — three files serving the same goal belong in one commit   |
| Pushing after executing the plan                                    | The skill ends at commit. Never push — the user controls that step          |
| Including out-of-scope files in a commit                            | Re-read the INCLUDE/EXCLUDE filter; stage only files that passed the filter |
