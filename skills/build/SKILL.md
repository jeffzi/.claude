---
name: build
description: >
  Designs a feature interactively and produces an approved plan file at .planning/plan-<slug>.md —
  never executes it.
argument-hint: "[feature description, or path to an existing spec]"
disable-model-invocation: true
model: opus
effort: high
---

# Build

**Feature:** $ARGUMENTS

Feature design pipeline: discuss → plan. The deliverable is an approved plan file at
`.planning/plan-<slug>.md`. Execution is out of scope — it happens later, in a separate session,
from the plan file alone.

## When to Use

Features and non-trivial behavior changes. Not for bug fixes — root cause needs investigation first;
use `/fix`.

## Skip Logic

When `$ARGUMENTS` is received, determine what to skip:

- **Not a path to an existing file** → treat as a feature description; run both phases.
- **A path to an existing file with `type: spec` frontmatter** → the design work is done: skip Phase
  1, proceed to Phase 2 with the spec as input.
- **A path to an existing file with `type: plan` frontmatter** → nothing left for /build: the plan
  is the deliverable and it already exists. Say so and stop. If the user wants the plan changed,
  they name the edits and the run enters Phase 2's edit loop on that file.
- **A path to an existing file with no `type:` field** → default to treating it as a **spec** (skip
  Phase 1 only — the least-aggressive skip), and say so: "No `type:` frontmatter found; treating
  `<path>` as a spec and skipping Phase 1. If it's actually a finished plan, /build has nothing to
  add."

Use frontmatter `type:` as the canonical discriminator. Do not infer type from file path, directory
name, or content patterns — a spec can live outside `specs/`, and a spec can contain "Task" in its
prose.

Skip Logic keys on `$ARGUMENTS` at invocation time only. A plan produced later in this run never
re-enters it — a plan written this session always goes through the approval gate, even though it
carries `type: plan` frontmatter.

## Architecture

Both phases run interactively in the **main context** — they need natural back-and-forth with the
user. The plan is written for an implementer with **zero prior context** (write-plan's own
contract): the plan file is the entire handoff to whichever session executes it, and the phase 1–2
dialogue never travels with it. Design decisions the executor must know belong in the plan, not in
this conversation.

The plan at `.planning/plan-<slug>.md` is the pipeline's single artifact.

This skill pins `model: opus` / `effort: high`, live on every invocation: phases 1–2 adjudicate
design in the main context — exactly where a cheaper tier rationalizes shallow discussion and
rubber-stamp plans. Violating the letter of any rule in this skill is violating its spirit — there
are no technicalities.

### Phase 1: Discuss

Design conversation, no artifact. Before any plan is drafted:

- Explore project context; ask clarifying questions **one at a time** — requirements, constraints,
  what already exists.
- Propose 2–3 approaches with trade-offs; converge on one with the user.
- Surface assumptions explicitly — simple features have unexamined ones.

The conversation itself is the design record that feeds Phase 2; decisions worth keeping land in the
plan's **Goal/Architecture** header, and the reasoning stays in this dialogue.

**Escape hatch — multi-plan features:** when the discussion reveals multiple independent subsystems
(the same condition as write-plan's Scope Check), a single plan header can't hold the design. Say
so, write a spec as the umbrella document at `.planning/spec-<slug>.md` — the agreed design,
subsystem boundaries, and cross-subsystem constraints from Phase 1 — then run Phase 2 once per
subsystem. Otherwise, never write a spec.

### Phase 2: Plan

Load `Skill(write-plan)` with the agreed design as input (and the spec path, when the escape hatch
produced one). write-plan owns the plan's format, task structure, and presentation protocol — do not
restate or override its rules here. Carry its plan path forward as `PLAN_PATH`.

**Approval gate:** present the plan inline — its full structure (goal, tasks, behaviors, Verify
blocks) so the user is not required to open the file — then use `AskUserQuestion` with two options
(if the tool is unavailable, ask the same two options in prose and wait; the gate is the
requirement, the tool is the vehicle):

- **Approve** → stop. /build's work ends at the approved plan — do not start any task "to get a head
  start"; execution happens in a separate session from the plan file.
- **Edit plan** → apply requested changes, re-present, repeat until approved.

**Checkpoint:** Confirm the plan file exists on disk at `PLAN_PATH` before closing. If it does not,
halt: "Plan approved but no plan file exists on disk."

## Red flags — you are rationalizing if

- You are starting "just Task 1" after approval — /build ends at the plan, always.
- You are summarizing the dialogue for a future executor instead of putting the decision in the
  plan.
- You are writing a spec for a feature that fits one plan.

## Common Mistakes

| Mistake                                            | Fix                                                                              |
| -------------------------------------------------- | -------------------------------------------------------------------------------- |
| Skipping the discussion because "it's obvious"     | Simple features have unexamined assumptions. Run Phase 1.                        |
| Writing a spec for a single-plan feature           | The plan header is the design record. Specs are for multi-plan features only.    |
| Implementing after approval "while it's fresh"     | The deliverable is the plan file. Execution belongs to a separate session.       |
| Leaving a key design decision in the dialogue      | The plan is the entire handoff — if the executor must know it, the plan says it. |
| Treating a `type: plan` argument as a work request | The plan exists; /build has nothing to add. Say so and stop.                     |

Pressure scenarios for these rules, with run results: `references/pressure-tests.md`.
