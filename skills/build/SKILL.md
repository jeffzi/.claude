---
name: build
description: >
  Use when building a new feature, component, or non-trivial behavior change end-to-end. Not for
  bug fixes (use /fix).
argument-hint: "[feature description, or path to an existing spec/plan]"
disable-model-invocation: true
model: opus
effort: high
---

# Build

**Feature:** $ARGUMENTS

End-to-end feature pipeline: discuss → plan → dispatch execution to a `plan-executor` agent in a
fresh context.

## When to Use

Features and non-trivial behavior changes. Not for bug fixes — root cause needs investigation first;
use `/fix`.

## Skip Logic

When `$ARGUMENTS` is received, determine what to skip:

- **Not a path to an existing file** → treat as a feature description; run all phases.
- **A path to an existing file with `type: spec` frontmatter** → the design work is done: skip Phase
  1, proceed to Phase 2 with the spec as input.
- **A path to an existing file with `type: plan` frontmatter** → the invocation is itself the
  execution request: set `PLAN_PATH` to the absolute resolved path of `$ARGUMENTS`, skip Phases 1–2
  **and the approval gate**, and dispatch Phase 3 immediately.
- **A path to an existing file with no `type:` field** → default to treating it as a **spec** (skip
  Phase 1 only — the least-aggressive skip), and say so: "No `type:` frontmatter found; treating
  `<path>` as a spec and skipping Phase 1. If it's actually a plan, tell me to skip planning too."

Use frontmatter `type:` as the canonical discriminator. Do not infer type from file path, directory
name, or content patterns — a spec can live outside `specs/`, and a spec can contain "Task" in its
prose.

Skip Logic keys on `$ARGUMENTS` at invocation time only. A plan produced later in this run never
re-enters it — a plan written this session always goes through the approval gate, even though it
carries `type: plan` frontmatter.

## Architecture

Phases 1–2 (design discussion, planning) run interactively in the **main context** — they need
natural back-and-forth with the user. Phase 3 runs inside a **`plan-executor` agent with a fresh
context**: the phase 1–2 dialogue never enters it, and the plan file is the entire handoff. Plans
are written for an implementer with zero prior context (write-plan's own contract), so the executor
needs nothing from this conversation — do not summarize the discussion into the dispatch prompt.

The plan at `.planning/plan-<slug>.md` is the pipeline's single artifact. There is no separate spec
document unless the escape hatch in Phase 1 fires.

This skill pins `model: opus` / `effort: high`, live on every invocation: phases 1–2 adjudicate
design in the main context, and the dispatch and relay rules below are exactly where a cheaper tier
rationalizes. Violating the letter of any rule in this skill is violating its spirit — there are no
technicalities.

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
so, load `Skill(brainstorming)` to write a real spec as the umbrella document, then run Phase 2 once
per subsystem. Otherwise, never write a spec.

### Phase 2: Plan

Load `Skill(write-plan)` with the agreed design as input (and the spec path, when the escape hatch
produced one). The plan lands at `.planning/plan-<slug>.md`; carry that path forward as `PLAN_PATH`.
write-plan owns the plan's format and task structure — do not restate or override its rules here.

**Approval gate:** Present the plan inline — its full structure (goal, tasks, behaviors, Verify
blocks) so the user is not required to open the file — then use `AskUserQuestion` with three options
(if the tool is unavailable, ask the same three options in prose and wait; the gate is the
requirement, the tool is the vehicle):

- **Approve & execute** → dispatch Phase 3 now.
- **Approve, don't execute** → stop. Confirm `PLAN_PATH` and how to run it later:
  `/build <plan-path>`. Do not dispatch anything, do not start any task "to get a head start."
- **Edit plan** → apply requested changes, re-present, repeat until approved.

**Checkpoint:** Confirm the plan file exists on disk at `PLAN_PATH` before dispatching. If it does
not, halt: "Plan approved but no plan file exists on disk."

### Phase 3: Execute — dispatch, never inline

Dispatch **one** Agent call:

- `subagent_type: plan-executor` — do NOT set `model`; the agent definition pins `opus` at high
  effort.
- Dispatch with `run_in_background: true` — the relay protocol depends on an addressable, resumable
  agent, not a blocking call.
- Prompt contains exactly: the absolute `PLAN_PATH`, the project root, and — only when a spec file
  exists — its absolute path. Nothing else — no design summaries, no task restatements, no advice
  distilled from the dialogue.

The executor owns the whole implementation pipeline: TDD orchestration, spec-compliance gate,
code-quality gates, commits, and per-task verification. Its contract lives in
`~/.claude/agents/plan-executor.md`.

**Halt condition:** If the dispatch errors or the `plan-executor` agent type is unavailable, stop
and surface it. One retry is permitted for a transient error; an absent agent type is not transient.
The halt is unconditional — no amount of retrying or effort spent converts inline execution into a
"last resort." Never run the pipeline inline in this context — inline execution drags the phase 1–2
dialogue into every implementation decision and is exactly what the dispatch exists to prevent.

| Excuse                                                          | Reality                                                                                                                 |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| "The user approved execution — the agent is just a wrapper"     | They approved this pipeline: fresh context, gates, executor. A substitute mechanism is a new decision, and it's theirs. |
| "I already have TDD knowledge in context — that's a head start" | Parent context is the contaminant the dispatch removes. Readiness here is the symptom, not an asset.                    |
| "The session is long — dispatching risks compaction mid-relay"  | Compaction is the harness's problem. Inline guarantees the contamination the dispatch merely risks.                     |
| "An executor for one small task is heavy"                       | The dispatch was priced in when this pipeline was designed. Cost is not a veto.                                         |
| "I retried and it still fails — inline is the last resort"      | The fallback is the violation; retries don't launder it. Surface and stop.                                              |

### While the executor runs — relay protocol

The executor stops and reports whenever it needs a human decision — a `NEEDS_INPUT` block with
`QUESTION` / `CONTEXT` / `PROGRESS` fields (ambiguous requirement, STUCK, PASSED_UNEXPECTEDLY,
TEST_FLAWED, a gate that failed twice). When that arrives:

1. Relay the question to the user **verbatim**, with the executor's context summary.
2. Wait for the user's answer — however long that takes.
3. Send the answer back to the **same** executor agent (SendMessage), so it resumes with its
   accumulated implementation context intact.

Never answer on the user's behalf, however confident the phase 1–2 dialogue makes you. Never
dispatch a fresh executor to "avoid it getting stuck again" — a fresh dispatch discards every task's
context and still requires the very answer you were avoiding.

| Excuse                                                      | Reality                                                                                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| "I'm 80% sure what the user would say — keep things moving" | 20% is a one-in-five chance of shipping the wrong behavior under a commit that says it's done. Relay.                                            |
| "If I'm wrong it's a small change — we can flip it later"   | By the next task the guess is baked into schema, tests, and call sites.                                                                          |
| "The executor got stuck — a better prompt won't stall"      | Writing that "better prompt" requires the decision only the user can make. That's answering on their behalf with extra steps, minus the context. |
| "The deadline — the user wanted this done tonight"          | A deadline is a preference; it never transfers decision rights.                                                                                  |

### Completion

When the executor's final report arrives, relay to the user: tasks completed, commits made, the
final suite result, and any unresolved verdicts or stopped work — in the executor's terms, verified
against `git log`, not embellished. Close by reminding the user to run `/preflight` before pushing.

## Red flags — you are rationalizing if

- You are drafting a sentence explaining why this particular dispatch is unnecessary.
- You are about to answer an executor question from the phase 1–2 dialogue.
- You are adding anything beyond paths and the project root to the dispatch prompt.
- You are starting "just Task 1" after an "Approve, don't execute".
- You are writing a spec for a feature that fits one plan.

## Common Mistakes

| Mistake                                                | Fix                                                                                 |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| Skipping the discussion because "it's obvious"         | Simple features have unexamined assumptions. Run Phase 1.                           |
| Writing a spec for a single-plan feature               | The plan header is the design record. Specs are for multi-plan features only.       |
| Executing inline because "the plan is small"           | Size is not the point — fresh context is. One task inline is still a violation.     |
| Padding the dispatch prompt with dialogue summaries    | The plan is written for zero context. Extra context re-couples the phases.          |
| Treating "Approve, don't execute" as "execute quietly" | A deferred execution is deferred. Stop after confirming the path.                   |
| Answering an executor question from the dialogue       | Decisions route through the user — relay verbatim, wait, resume the same agent.     |
| Re-dispatching a fresh executor mid-plan               | SendMessage to the existing agent preserves its context; a fresh dispatch loses it. |

Pressure scenarios for these rules, with run results: `references/pressure-tests.md`.

## Resume

If the session ends or the executor is interrupted mid-plan, completed work survives as atomic
commits. Re-invoke `/build <plan-path>` — the new executor works through the plan from the top, and
tasks already implemented surface as `PASSED_UNEXPECTEDLY` at their first TDD cycle, which the
executor routes to you as a question (answer "already implemented — skip"). Provide a spec path
instead to re-enter at Phase 2 (escape-hatch features only).
