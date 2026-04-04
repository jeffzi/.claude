---
name: write-plan
description: >
  Use when you have a spec or requirements for a multi-step task, before touching code.
  Also use when asked to create an implementation plan or invoked via /write-plan.
  Not for single-task changes or quick bug fixes that need no plan.
---

# Writing Plans

## Overview

Write implementation plans that describe **what to build**, not how to TDD it. Each task is a
vertical slice — a behavior or cohesive group of behaviors that could ship independently.

Assume the implementing agent is skilled but has zero context for the codebase or problem domain.
Document which files to touch, what behaviors to implement, and what to watch out for.

## Scope Check

If the spec covers multiple independent subsystems, suggest breaking into separate plans — one per
subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each is responsible
for. This is where decomposition decisions get locked in.

- One clear responsibility per file. Prefer smaller, focused files.
- Files that change together should live together. Split by responsibility, not by layer.
- In existing codebases, follow established patterns.

This structure informs task decomposition. Each task should produce self-contained changes.

## Task Granularity

Each task is a **behavior group** — one behavior or a cohesive batch of related behaviors that share
the same implementation area. Tasks describe **what** to build, not **how** to test it.

**Good task:** "Implement email validation: reject empty, malformed, and duplicate emails."

**Bad task:** "Step 1: Write failing test for empty email. Step 2: Run test. Step 3: Implement
validation. Step 4: Run test. Step 5: Commit."

## Plan Document Header

Every plan starts with:

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Skills:** [Language/tech skills to load before implementation, e.g. `code-py`, `test-py`]

---
```

## Task Structure

```markdown
### Task N: [Component Name]

**Files:**

- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py`
- Test: `tests/exact/path/to/test.py`

**Behaviors:**

- [Behavior 1: what it does, expected inputs/outputs]
- [Behavior 2: edge case or validation rule]
- [Behavior 3: error handling]

**Notes:** [Non-obvious constraints, dependencies on prior tasks, gotchas]

**Implementation:** Use `/tdd` for implementation.
```

## What Goes in a Plan vs. What Doesn't

| In the plan                | NOT in the plan              |
| -------------------------- | ---------------------------- |
| Behaviors to implement     | Test assertions or test code |
| Files to create/modify     | Implementation code          |
| Dependencies between tasks | RED/GREEN/REFACTOR steps     |
| Non-obvious constraints    | Commit messages              |
| Architecture decisions     | TDD mechanics                |
|                            | Internal skill/agent names   |

## Plan Review

For plans with 4+ tasks, dispatch a reviewer subagent to check completeness, spec alignment, and
task decomposition. Max 3 review iterations, then surface to user. Reviewers are advisory.

For smaller plans, review inline before presenting to the user.
