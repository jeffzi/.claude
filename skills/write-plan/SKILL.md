---
name: write-plan
description: >
  Use when you have a spec or requirements for a multi-step task, before touching code.
  Also use when asked to create an implementation plan, invoked via /write-plan, or about
  to enter plan mode — this skill replaces plan mode.
  Not for single-task changes or quick bug fixes that need no plan.
argument-hint: "[task or spec]"
---

# Writing Plans

**Violating the letter of these rules is violating their spirit.**

## No Plan Mode

This skill replaces plan mode. **Never call `EnterPlanMode`, and never steer the user into entering
plan mode for you** — the ban is unconditional and covers the whole session. Plan mode writes to a
harness-assigned file outside the project and erases context on approval, stranding the Checkpoint.
Write the plan to `.planning/plan-<slug>.md` instead (see Checkpoint) — creating it is prescribed,
not an unrequested edit.

| Excuse                                             | Reality                                                              |
| -------------------------------------------------- | -------------------------------------------------------------------- |
| "The harness reminder suggests plan mode"          | Generic advice; this skill overrides it.                             |
| "We always used plan mode for planning here"       | Precedent is not permission — every such plan was stranded.          |
| "Plan mode gives me a plan file for free"          | That file lives outside the project; it's the cost, not the benefit. |
| "I'll enter plan mode first, then load the skill"  | Pre-load entry is the same violation, not a recovery trigger.        |
| "I can still write to `.planning/` from plan mode" | Satisfying the ban's rationale does not lift the ban.                |

Plan mode already active? See `references/plan-mode-recovery.md`. Entered it yourself? Same routing
after disclosing the violation.

## Scope and Files

Multiple independent subsystems → suggest one plan per subsystem. Before defining tasks, map
created/modified files and each file's single responsibility — files that change together live
together. Done when every touched file sits in exactly one task's **Files** list.

## Tasks and Behaviors

Each task is a **behavior group** — behaviors sharing one implementation area; tasks say **what** to
build, never how to test it:

```text
Good task: "Implement email validation: reject empty, malformed, and duplicate emails."
Bad task:  "Step 1: Write failing test for empty email. Step 2: Run test. Step 3: Implement…"
```

Word behaviors per `references/behavior-wording.md`: observable outcomes, never mechanisms;
flag-gated → both branches with coverage each; drop mechanism, never outcome. Done when every spec
requirement sits in exactly one task's **Behaviors** list.

## Plan Header

```markdown
---
type: plan
---

# [Feature Name] Implementation Plan

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Skills:** [Only when the project has no test suite and tasks are implemented directly — skills to
load before implementation. Tasks routed through `/tdd` omit this line; the agents resolve language
skills themselves.]

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

**Verify:** After implementation is complete and before committing, dispatch a `claim-reviewer`
agent with this task's behavioral claims. Fix any `Refuted`/`Unsubstantiated` verdicts before
committing.
```

The **Verify** block goes on every task except the one directly before the Final Task — the Final
Task re-verifies it immediately. Token pressure never removes **Verify** from an earlier task; a
single-task plan has only the Final Task.

## Final Verification Task

Every plan ends with this task, verbatim except the claims:

```markdown
### Final Task: Verify Implementation

After all tasks are complete, run a final whole-plan review. Dispatch a single **Agent** call with
`subagent_type: claim-reviewer` (do NOT set model — the agent defines its own). Extract one claim
per behavior across **all** tasks, stated as implemented fact:

Claim N: [behavior from Task M, e.g. "email validation rejects empty, malformed, and duplicate
emails"] Location: [file the task created/modified]

Word every claim as the observable outcome the behavior promises: a claim the reviewer can confirm
by finding a call site, without tracing what it produces, is worded wrong. A flag-gated behavior
yields a claim covering both branches.

This catches cross-task integration issues that per-task verification misses (e.g. Task 3 broke Task
1's behavior). For any `Refuted` or `Unsubstantiated` verdict, fix the gap and re-verify that claim
once; if it still fails, surface it to the user. Mechanical claims (tests pass, build green) are not
for the reviewer — verify those by running the commands directly. Close by reminding the user to run
`/preflight` before pushing — plan execution defers the deep review lenses to it.
```

## Test-Only Plans

When every task's deliverable is test code with **no production-code changes**, `/tdd` is the
**only** step the plan may omit — replace **Implementation** with the concrete change. **Verify**
(same before-Final-Task exception as Task Structure) and the Final Task `claim-reviewer` **still run
— no plan ever skips them**; claims cover what each test now exercises and asserts.

| Excuse                                                      | Reality                                                                                                                                                                                                                            |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "A green suite proves the tests assert the right thing"     | Running the suite proves the tests _pass_, never that they assert the _correct_ behavior — a test can pass while checking the wrong thing. That gap is a behavioral claim, never mechanical; it is exactly `claim-reviewer`'s job. |
| "Convention here is to skip review on test-only fixes"      | Any plan that skipped it was non-compliant. Precedent is not permission.                                                                                                                                                           |
| "I already read every cited line, so the pass is redundant" | You verified your own work; independent review catches what your reading missed. Confidence is not evidence.                                                                                                                       |
| "Low-risk cleanup — the reviewer's time is expensive"       | Risk and cost do not change the rule. `claim-reviewer` runs on every plan.                                                                                                                                                         |

## Plan Contents

| In the plan                                     | NOT in the plan              |
| ----------------------------------------------- | ---------------------------- |
| Behaviors to implement                          | Test assertions or test code |
| Files to create/modify                          | Implementation code          |
| Dependencies between tasks                      | RED/GREEN/REFACTOR steps     |
| Non-obvious constraints                         | Commit messages              |
| Architecture decisions                          | TDD mechanics                |
| Execution directives (`/tdd`, `claim-reviewer`) |                              |

## Review Before Presenting

Run both passes per `references/plan-review.md` in one parallel message: the advisory plan review
(2+ tasks) and **Verify Plan Claims — mandatory on every plan, including test-only ones** — dispatch
`claim-reviewer` (no model set), one claim per checkable assertion about existing code;
`Refuted`/`Unsubstantiated` → re-check once, correct or cite evidence.

## Checkpoint

Create the plan at `.planning/plan-<slug>.md` **as the working file from the first draft**; draft,
review, and revise there (`<slug>` kebab-cased from the feature). When ready, present it in
conversation and wait for explicit approval before implementation. Approval happens in conversation,
not via `ExitPlanMode`: ask explicitly ("Approve this plan?") and wait — silence, a tangent, or a
question is not approval.

## Red Flags

| Red flag — you are rationalizing if                                            |
| ------------------------------------------------------------------------------ |
| Drafting a sentence explaining why this plan doesn't need `claim-reviewer`     |
| About to call `EnterPlanMode` or suggest the user toggle plan mode             |
| Drafting plan content in conversation instead of in `.planning/plan-<slug>.md` |
| Removing a **Verify** block to shorten the plan                                |
| Treating a question, tangent, or silence as approval                           |
| Putting test assertions, implementation code, or RED/GREEN steps into a task   |

## Common Mistakes

| Mistake                                              | Reality                                                                    |
| ---------------------------------------------------- | -------------------------------------------------------------------------- |
| One task per file instead of per behavior group      | Group by coherent behavior, not by file boundary                           |
| All changes in one task because they're related      | Independent subsystems → separate tasks (or separate plans)                |
| Skipping the file structure section                  | Without file mapping, decomposition decisions are deferred and conflicting |
| Plan documents the obvious (CRUD, standard patterns) | Only document non-obvious constraints, gotchas, and dependencies           |
