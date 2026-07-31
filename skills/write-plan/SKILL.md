---
name: write-plan
description: >
  Use when you have a spec or requirements for a multi-step task, before touching code.
  Also use when asked to create an implementation plan or invoked via /write-plan.
  Not for single-task changes or quick bug fixes that need no plan.
argument-hint: "[task or spec]"
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
---
type: plan
---

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

**Verify:** After the task is complete, dispatch a `claim-reviewer` agent with this task's
behavioral claims. Fix any `Refuted`/`Unsubstantiated` verdicts first.
```

The **Verify** block goes on every task **except the last implementation task** — the Final Task
re-verifies that task's claims immediately after it, and no later task builds on it, so a per-task
pass there is pure overlap. The exception covers exactly one task: the one directly before the Final
Task. Token pressure never removes **Verify** from any earlier task — those have dependents, and a
defect caught late costs rework in every task built on it. A single-task plan has no per-task
**Verify** at all; the Final Task is its verification.

## Final Verification Task

Every plan ends with this task, verbatim except for the claims:

```markdown
### Final Task: Verify Implementation

After all tasks are complete, run a final whole-plan review. Dispatch a single **Agent** call with
`subagent_type: claim-reviewer` (do NOT set model — the agent defines its own). Extract one claim
per behavior across **all** tasks, stated as implemented fact:

Claim N: [behavior from Task M, e.g. "email validation rejects empty, malformed, and duplicate
emails"] Location: [file the task created/modified]

This catches cross-task integration issues that per-task verification misses (e.g. Task 3 broke Task
1's behavior), and it is the sole claim verification for the last implementation task. For any
`Refuted` or `Unsubstantiated` verdict, fix the gap and re-verify that claim once; if it still
fails, surface it to the user. Mechanical claims (tests pass, build green) are not for the reviewer
— verify those by running the commands directly. Close by reminding the user to run `/preflight`
before pushing — plan execution defers the deep review lenses to it.
```

## Test-Only Plans

When every task's deliverable is test code — fixing, adding, or repairing tests with **no
production-code changes** — the red-green cycle does not apply: there is no production behavior to
drive from a failing test, and the tests are themselves the deliverable. `/tdd` is the **only** step
a test-only plan may omit. Adapt the task template; drop nothing else:

- **Implementation:** replace `Use /tdd` with the concrete change the task makes.
- **Verify** and **Final Task:** `claim-reviewer` **still runs — no plan ever skips it** (the
  last-task **Verify** omission applies as usual; the Final Task covers that task). A passing suite
  is a mechanical claim (run it directly) and does **not** prove a test asserts the right thing; a
  green test can check the wrong behavior. Extract claims about what each test now exercises and
  asserts (e.g. "the bucketing test covers all three buckets") and let the independent review verify
  them.

No matter how thoroughly the main agent reviewed its own work, independent review is required. The
factual claim-verification pass below also runs regardless: a test-only plan still asserts facts
about existing code.

These are bright-line rules — "lean", "low-risk", "just tests", and "that's how we do it here" are
not exceptions. The rationalizations that surface under pressure, and why each fails:

| Excuse                                                      | Reality                                                                                                                                                                                                                            |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "A green suite proves the tests assert the right thing"     | Running the suite proves the tests _pass_, never that they assert the _correct_ behavior — a test can pass while checking the wrong thing. That gap is a behavioral claim, never mechanical; it is exactly `claim-reviewer`'s job. |
| "Convention here is to skip review on test-only fixes"      | Any plan that skipped it was non-compliant. Precedent is not permission.                                                                                                                                                           |
| "I already read every cited line, so the pass is redundant" | You verified your own work; independent review catches what your reading missed. Confidence is not evidence.                                                                                                                       |
| "Low-risk cleanup — the reviewer's time is expensive"       | Risk and cost do not change the rule. `claim-reviewer` runs on every plan.                                                                                                                                                         |

## What Goes in a Plan vs. What Doesn't

| In the plan                | NOT in the plan              |
| -------------------------- | ---------------------------- |
| Behaviors to implement     | Test assertions or test code |
| Files to create/modify     | Implementation code          |
| Dependencies between tasks | RED/GREEN/REFACTOR steps     |
| Non-obvious constraints    | Commit messages              |
| Architecture decisions     | TDD mechanics                |
|                            | Internal skill/agent names   |
| Execution directives       |                              |
| (`/tdd`, `claim-reviewer`) |                              |

## Plan Review

For plans with 2+ tasks, dispatch one **Agent** call with `subagent_type: general-purpose` and
`model: sonnet`, passing the spec and the draft plan, to check completeness, spec alignment, and
task decomposition. The model is pinned because this agent checks a written plan against a supplied
spec rather than diagnosing anything. Max 3 review iterations, then surface to user. Reviewers are
advisory.

This review is independent of claim verification below — send both agents in a single message so
they run in parallel.

For smaller plans, review inline before presenting to the user.

## Verify Plan Claims

A plan asserts facts about the codebase — files it will modify already exist, named symbols are
present, the current code behaves as described, a pattern to follow lives where the plan says. A
plan built on a stale or wrong assumption sends the implementer down a dead end. Before presenting
the plan, verify these factual claims independently.

This pass is **mandatory** and runs no matter how carefully you read the code while investigating.
"I already verified each cited line myself during investigation" is not grounds to skip it — that is
you checking your own work, which is exactly what an independent pass exists to catch. Confidence is
not evidence. Dispatch the agent every time, including for test-only plans.

Dispatch a single **Agent** tool call with `subagent_type: claim-reviewer` (do NOT set model — the
agent defines its own). Extract one claim per checkable assertion the plan makes about existing
code:

```text
Claim N: [the plan's factual assertion about the codebase]
Location: [file:line or symbol the claim names, if any]
```

The agent returns a `### Claim N` block per claim (`Verdict: Verified | Refuted | Unsubstantiated`,
`Score`, `Evidence`, `Reasoning`). For any `Refuted` or `Unsubstantiated` verdict, re-check the
claim against the code once: if the reviewer is right, correct the plan — fix the path, re-scope the
task, or drop the assumption — before presenting it; if your re-check confirms the claim, keep it
and cite the confirming evidence in the plan. Do not feed the agent claims about code the plan will
_create_; it can only verify what exists now.

## Checkpoint

After the plan is approved and written to disk, confirm the artifact path for handoff to downstream
tools.

## Common Mistakes

| Mistake                                                     | Reality                                                                    |
| ----------------------------------------------------------- | -------------------------------------------------------------------------- |
| Tasks describe TDD steps ("write failing test", "run test") | Tasks describe **behaviors**, not test mechanics                           |
| One task per file instead of per behavior group             | Group by coherent behavior, not by file boundary                           |
| Implementation code or test assertions in the plan          | Plans describe what to build, not how to implement                         |
| All changes in one task because they're related             | Independent subsystems → separate tasks (or separate plans)                |
| Skipping the file structure section                         | Without file mapping, decomposition decisions are deferred and conflicting |
| Plan documents the obvious (CRUD, standard patterns)        | Only document non-obvious constraints, gotchas, and dependencies           |
