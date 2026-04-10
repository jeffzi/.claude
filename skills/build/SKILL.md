---
name: build
description: >
  Use when building a new feature, component, or non-trivial behavior change end-to-end in a single
  session. Not for bug fixes (use /fix) or multi-session features (use GSD).
argument-hint: "[feature or behavior to build]"
disable-model-invocation: true
model: sonnet
effort: high
---

# Build

**Feature:** $ARGUMENTS

End-to-end feature pipeline: brainstorm → plan → implement with quality gates.

## When to Use

| Scope                          | Tool                                                  |
| ------------------------------ | ----------------------------------------------------- |
| Bug fix                        | `/fix` — investigates root cause, then TDD            |
| Small feature (single session) | `/build` — this skill                                 |
| Large feature (multi-session)  | GSD — disk-persistent planning, cross-session context |

**Not for:**

- Bug fixes — root cause needs investigation first, use `/fix`
- Features requiring multiple sessions or parallel workstreams — use GSD

## Skip Logic

At the start, check what the user already has:

- **User provides a spec or design doc** → skip Phase 1, proceed to Phase 2
- **User provides a plan** → skip Phases 1–2, proceed to Phase 3
- **No prior context** → run all phases

## Process

**Do NOT investigate, read code, or form implementation opinions in the main context.** Each phase
is dispatched to maintain context isolation. The orchestrator coordinates; skills do the work.

### Phase 1: Brainstorm

Load `Skill(brainstorming)`. This skill guides collaborative design:

- Explore project context, ask clarifying questions one at a time
- Propose 2–3 approaches with trade-offs
- Present design sections for incremental approval
- Write a spec document and self-review it

**Human checkpoint:** Wait for user approval of the written spec before proceeding.

### Phase 2: Plan

Load `Skill(write-plan)` in the main context with the approved spec as input.

The plan must describe **behaviors to implement**, not implementation details. Each task ends with
"Use `/tdd` for implementation." No inline RED/GREEN steps or code in task descriptions.

**Human checkpoint:** Present the plan and wait for user approval before execution.

### Phase 3: Execute

For each task in the plan:

#### Step 1: Implement

Load `Skill(tdd)` with the task description. The TDD orchestrator handles RED-GREEN-REFACTOR.
Capture from the result:

- `TEST_COMMAND`, `FULL_SUITE_COMMAND`, `IMPLEMENTATION_FILES`, `TEST_FILE`

If `STATUS: STUCK` → surface to user with diagnostics. Do not proceed to review. If
`STATUS: PASSED_UNEXPECTEDLY` → report to user. Ask: skip or revise scope?

#### Step 2: Spec compliance review (gate)

Dispatch a subagent (`model: sonnet, effort: high`) using the prompt template at
`${CLAUDE_SKILL_DIR}/references/spec-reviewer-prompt.md`.

Provide:

- **Task spec**: the task description from the plan (behaviors, not implementation)
- **Implementation files**: `IMPLEMENTATION_FILES` from tdd result
- **Test files**: `TEST_FILE` from tdd result

Check `SPEC_STATUS` in the response:

- `PASS` → proceed to Step 3
- `FAIL` → the same tdd context cannot fix tests; dispatch a fresh subagent
  (`model: sonnet, effort: high`) to fix implementation gaps, then re-dispatch spec review. After 2
  failed iterations, surface to user.

#### Step 3: Code quality review (gate)

Dispatch in parallel (two independent agents, `model: sonnet, effort: medium`):

- **Agent A:** `/vet-code` on `IMPLEMENTATION_FILES`
- **Agent B:** `/vet-test` on `TEST_FILE`

For each finding, apply the fix directly in the main context — vet-code/vet-test findings are code
quality issues, not new behaviors, so no TDD cycle is required. After all fixes are applied, re-run
`TEST_COMMAND` to confirm tests still pass.

#### Step 4: Mark task complete

Run `FULL_SUITE_COMMAND` once per task to catch regressions before starting the next.

### Phase 4: Final verification

After all tasks complete:

1. Run `FULL_SUITE_COMMAND` — confirm full suite passes
2. `git diff --stat` to summarize all changes

## Common Mistakes

| Mistake                                                | Fix                                                                           |
| ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| Skipping brainstorm because "it's obvious"             | Simple features have unexamined assumptions. Run Phase 1.                     |
| Skipping spec review because "TDD already verified it" | TDD verifies the test passes. Spec review verifies the right thing was built. |
| Proceeding after STUCK                                 | Surface diagnostics to user. Don't retry blindly.                             |
| Running Phase 3 without approved plan                  | Phases 1–2 gates exist to prevent building the wrong thing.                   |
