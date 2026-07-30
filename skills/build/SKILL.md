---
name: build
description: >
  Use when building a new feature, component, or non-trivial behavior change end-to-end in a single
  session. Not for bug fixes (use /fix).
argument-hint: "[feature or behavior to build]"
disable-model-invocation: true
model: opus
effort: high
---

# Build

**Feature:** $ARGUMENTS

End-to-end feature pipeline: brainstorm → plan → implement with quality gates.

## When to Use

| Scope                          | Tool                                       |
| ------------------------------ | ------------------------------------------ |
| Bug fix                        | `/fix` — investigates root cause, then TDD |
| Small feature (single session) | `/build` — this skill                      |

**Not for:**

- Bug fixes — root cause needs investigation first, use `/fix`

## Skip Logic

When `$ARGUMENTS` is received, determine what to skip:

- **Not a path to an existing file** → treat as a feature description; run all phases.
- **A path to an existing file with `type: spec` frontmatter** → skip Phase 1, proceed to Phase 2.
- **A path to an existing file with `type: plan` frontmatter** → skip Phases 1–2, proceed to
  Phase 3.
- **A path to an existing file with no `type:` field** → default to treating it as a **spec** (skip
  Phase 1 only — the least-aggressive skip), and say so: "No `type:` frontmatter found; treating
  `<path>` as a spec and skipping Phase 1. If it's actually a plan, tell me to skip planning too."

Use frontmatter `type:` as the canonical discriminator. Do not infer type from file path, directory
name, or content patterns — a spec can live outside `specs/`, and a spec can contain "Task" in its
prose.

## Process

All artifacts (specs, plans) are written to `.build/` at the project root. Create the directory if
it does not exist.

Phases 1–2 (brainstorming, planning) run interactively in the **main context** — brainstorming is
conversational and needs natural back-and-forth. Phase 3 achieves **partial** isolation via
`tdd-cycle` subagents for RED-GREEN, plus subagents for spec review and code-quality gates. The
orchestrator carries forward only artifact paths and status variables between phases; once a phase
completes, its dialogue is not referenced again.

### Phase 1: Brainstorm

Load `Skill(brainstorming)`. This skill guides collaborative design:

- Explore project context, ask clarifying questions one at a time
- Propose 2–3 approaches with trade-offs
- Present design sections for incremental approval
- Write a spec document and self-review it
- Present the full spec content inline in the conversation (do not ask the user to open a file)

**Human checkpoint:** Present the spec inline, then use `AskUserQuestion` with two options:
**Accept** (proceed to Phase 2) or **Edit** (apply requested changes, re-present, repeat until
accepted).

**Checkpoint:** After brainstorming completes, confirm the spec was written to `.build/`.

**Hand-off:** Prioritize the spec path and feature description; do not re-derive implementation
details from Phase 1 dialogue.

### Phase 2: Plan

Load `Skill(write-plan)` with `SPEC_PATH` as input so the spec location is unambiguous.

The plan must describe **behaviors to implement**, not implementation details. Each task ends with
"Use `/tdd` for implementation." No inline RED/GREEN steps or code in task descriptions.

**Human checkpoint:** Present the plan inline, then use `AskUserQuestion` with two options:
**Accept** (proceed to Phase 3) or **Edit** (apply requested changes, re-present, repeat until
accepted).

**Checkpoint:** After the plan is approved, confirm it was written to `.build/`.

**Hand-off:** Prioritize the plan path and the task list (descriptions only); do not re-derive
design decisions from Phase 2 dialogue.

### Phase 3: Execute

For each task in the plan:

#### Step 1: Implement

Load `Skill(tdd)` with the task description. The TDD orchestrator handles RED-GREEN-REFACTOR.

If the TDD result indicates `STATUS: STUCK` → surface to user with diagnostics. Do not proceed to
review. If `STATUS: PASSED_UNEXPECTEDLY` → report to user. Ask: skip or revise scope?

**Checkpoint:** After TDD completes successfully, proceed to spec compliance review.

#### Step 2: Spec compliance review (gate)

Dispatch a subagent (`model: sonnet, effort: high`) using the prompt template at
`${CLAUDE_SKILL_DIR}/references/spec-reviewer-prompt.md`.

Provide:

- **Task spec**: the task description from the plan (behaviors, not implementation)
- **Implementation files**: the files created or modified by the TDD phase
- **Test files**: the test file(s) created during TDD

Check the response for a `SPEC_STATUS` field:

- `PASS` → proceed to Step 3
- `FAIL` → route remediation by issue prefix (see FAIL Path below), then re-dispatch spec review.
  After **2** failed iterations, surface to user with the full ISSUES list.

##### FAIL Path — prefix routing

Every issue in the `ISSUES:` list has a `Missing:`, `Extra:`, or `Misunderstood:` prefix. Route each
type differently:

- **`Missing:`** → requirement not implemented. Dispatch a `tdd-cycle` agent (do NOT set model — the
  agent defines its own) for the missing behavior. Reuse existing test files where the behavior
  belongs in an already-tested module; create new test files for new concerns. When ambiguous,
  prefer a new file — a misplaced test is harder to fix than an extra file.
- **`Extra:`** → YAGNI violation. Dispatch a fixer subagent (`model: sonnet, effort: high`) to
  remove the unneeded code.
- **`Misunderstood:`** → wrong interpretation. Dispatch a fixer subagent
  (`model: sonnet, effort:
  high`); if the correct interpretation is ambiguous, surface to the user
  rather than guess.

**Mixed-issue handling** (a single FAIL can carry all three prefixes):

1. **Default — independent issues:** dispatch `tdd-cycle` (no model) for each `Missing:` behavior
   first (adds code + tests), then **one** fixer subagent (`model: sonnet, effort: high`) for the
   `Extra:` + `Misunderstood:` set (batched — they remove/change code).
2. **When a `Missing:` behavior builds on code a `Misunderstood:` issue corrects** (same function or
   region — check the `file:line` refs): fix the `Misunderstood:` issue **first**, so `tdd-cycle`
   writes tests against the corrected foundation. Handle `Extra:` removals in that same
   `model: sonnet, effort: high` fixer pass.
3. Re-run `TEST_COMMAND` after all fixes to confirm tests still pass. If a fix breaks a just-built
   test, surface to the user rather than retrying.
4. Re-dispatch the spec reviewer **once**.

Never run issues in parallel — the add-then-modify dependency is real, and parallel fixers can race
on the same file.

#### Step 3: Code quality review (gate)

Dispatch in parallel (three independent **Agent** calls — do NOT set model, the agents define their
own):

- **Agent A:** `subagent_type: vet-code` on implementation files from the TDD phase
- **Agent B:** `subagent_type: vet-test` on test files from the TDD phase
- **Agent C:** `subagent_type: vet-comments` on **both** sets of files

Agent C is not covered by the TDD phase's own comment review: that review sits inside REFACTOR,
which is skipped entirely under 50 insertions, so a small task reaches this gate with its
GREEN-phase comments unread.

All three reviewers are read-only. For each finding they return, apply the fix directly in the main
context — these are code quality issues, not new behaviors, so no TDD cycle is required. After all
fixes are applied, re-run the test suite to confirm tests still pass. If tests fail, revert the
offending fix and surface to the user.

#### Step 4: Mark task complete

Run the full test suite once per task to catch regressions before starting the next.

### Phase 4: Final verification

After all tasks complete:

1. Run the full test suite — confirm all tests pass
2. Run `git diff --stat` to summarize all changes

## Common Mistakes

| Mistake                                                | Fix                                                                           |
| ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| Skipping brainstorm because "it's obvious"             | Simple features have unexamined assumptions. Run Phase 1.                     |
| Skipping spec review because "TDD already verified it" | TDD verifies the test passes. Spec review verifies the right thing was built. |
| Proceeding after STUCK                                 | Surface diagnostics to user. Don't retry blindly.                             |
| Running Phase 3 without approved plan                  | Phases 1–2 gates exist to prevent building the wrong thing.                   |

## Resume

Build runs to completion in a single session; there is no resume mechanism. If interrupted, commit
your work, then re-invoke `/build` with the path to the completed artifact as the argument — provide
the spec path to skip Phase 1, or the plan path to skip Phases 1–2.
