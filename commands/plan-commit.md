---
description: >
  Analyze uncommitted changes and suggest a plan of granular, logical commits.
  Shows the plan for approval before any commits are made.
---

# Plan Commits

## Context

- All changes (staged, unstaged, untracked): !`git status --porcelain`
- Current git diff (staged and unstaged): !`git diff HEAD`
- Recent commits (for style reference): !`git log --oneline -10`
- Current branch: !`git branch --show-current`

## Your task

Analyze all uncommitted changes (staged, unstaged, and untracked files) and organize them into a
plan of **granular, logical commits** — each capturing one coherent unit of work.

### Step 1: Load the write-commit skill

Invoke `Skill(write-commit)` to load commit message guidelines before proceeding.

### Step 2: Analyze and group changes

Read the diffs and untracked files. Group them by logical purpose:

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

After presenting the plan, ask the user to confirm before executing:

- **(a)ccept** — execute all commits in order.
- **(e)dit** — the user describes what to change (regroup files, reword messages, merge/split
  commits) and you revise the plan before executing.
- **(c)ancel** — do nothing.

### Step 5: Execute (only after approval)

For each commit in the approved plan, stage only the listed files and commit. Use `write-commit`
guidelines for the final message. Execute commits sequentially — each must succeed before the next.

**Do not push.** The user will push when ready.
