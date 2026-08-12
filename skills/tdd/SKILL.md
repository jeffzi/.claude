---
name: tdd
description: >
  Use when implementing any feature, behavior change, or bug fix in a project with a test suite.
  Also use when asked to follow TDD or invoked via /tdd. Use when you think "I'll add tests later"
  — that's rationalization. Not for projects without a test suite. Not for bugs with unknown root
  cause — use /fix first (it investigates, then drives TDD).
argument-hint: "[feature or behavior to implement]"
---

# Test-Driven Development (TDD)

**Feature / Behavior:** $ARGUMENTS

## Overview

Write the test first. Watch it fail. Write minimal code to pass. Context-isolated via subagents.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## When to Use

TDD covers every feature, behavior change, bug fix, and refactor with behavior implications.
Exceptions exist, but the user grants them — ask before skipping TDD for:

- Throwaway prototypes
- Generated code
- Configuration files

## Plans and TDD

**Before creating any plan, load `Skill(write-plan)`.** Always. No exceptions.

When the project has a test suite, plans describe **behaviors to implement** plus the files they
touch — implementation details compromise the agents' context isolation; file paths do not (the
orchestrator hands `tdd-cycle` the test file paths anyway). When the project has no test suite,
plans describe implementation directly — TDD constraints don't apply.

## The Iron Law

No production code without a failing test first. See `references/philosophy.md` for the full
principles, rationalizations table, and red flags checklist.

## Architecture: Context-Isolated Subagents

Context isolation prevents the LLM from designing tests around planned implementation.

| Phase     | Agent                                       | Can see (Phase 1 / Phase 2)                      | Cannot see/modify                          |
| --------- | ------------------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| RED-GREEN | `tdd-cycle`                                 | Phase 1: tests, stubs, public API / Phase 2: all | Phase 1: impl source / Phase 2: test files |
| REFACTOR  | code-distiller → vet-comments → code-mender | Everything                                       | N/A (see REFACTOR section)                 |

Circuit-breaker tiers (3 failed GREEN attempts → new approach; 5 → STUCK) are defined in
`agents/tdd-cycle.md`; STUCK handling is `references/orchestration-flow.md` step 3.

### Mandatory Entry Point

**NEVER dispatch `tdd-cycle` directly.** This skill is the orchestrator — without it, no phase
verification, no circuit breaker, no structured data passing.

### Dispatch First — No Prep Tool Calls

**Within each cycle, the `tdd-cycle` dispatch is the first tool call.** Between the task's behavior
list and the Agent call there is nothing to read, run, or check: no Read, no Bash, no Glob, no Grep.
Every "prep" step you can name belongs elsewhere — language detection (TSTL markers, framework
checks) is the agent's hub dispatch; a baseline suite run duplicates work the agent's RED phase
owns; your own TEST_COMMAND runs come after the agent returns (Verify GREEN). Announcing the
dispatch is not the dispatch — only the Agent call is. Each tool call inserted before it is a step
out of the router role into the implementer role, and that drift ends with the orchestrator writing
RED tests inline while still believing it is about to dispatch.

| Excuse                                            | Reality                                                                          |
| ------------------------------------------------- | -------------------------------------------------------------------------------- |
| "Checking TSTL markers is routing, not reading"   | You pass paths, never a language. tdd-cycle's hubs route in its own context.     |
| "A green baseline confirms the suite works first" | tdd-cycle resolves and runs the commands in RED. Your first run is Verify GREEN. |
| "I said I'd dispatch — these reads are just prep" | The announcement is not the dispatch. Any prep before the Agent call is drift.   |

## Language Skill Dispatch

The orchestrator loads no testing or coding skills. `tdd-cycle` loads `Skill(test-core)` in its RED
phase and `Skill(code-core)` in its GREEN phase, inside its own context; each hub dispatches the
matching language leaf and the leaf auto-loads domain overlays. The orchestrator loads a hub only in
the fallback case where it must edit files itself (e.g., a REFACTOR mender skipped a finding you
then fix by hand) — `rules/skill-loading.md` applies as usual at that point.

**The orchestrator routes; it never reads target files.** Dispatch prompts carry behavior
descriptions and file paths; every agent reads its own files in its own fresh context. The only
contents the orchestrator loads are agent reports and the output of TEST_COMMAND /
FULL_SUITE_COMMAND. Reading a test or implementation file "to understand the API", "to batch
better", "to detect the language", or "before dispatching" is context stolen from the steps only the
orchestrator can do — verification, triage, commits. Batching is decided from the plan's behavior
list, never from file contents. If the extension has no dispatch row in `rules/skill-loading.md`,
the agent notes "no matching skill" and proceeds on hub principles alone.

`tdd-cycle` resolves TEST_COMMAND and FULL_SUITE_COMMAND during its RED phase — the orchestrator
uses these for independent GREEN verification.

## Batching: Cohesive vs. Unrelated

Each RED-GREEN cycle covers a **behavior group** — one behavior or a batch of related behaviors that
share the same implementation area. Isolation is a property of the **dispatch**, not the behavior:
one RED that writes tests for three behaviors landing in the same module loses nothing, and every
dispatch re-pays the agent's fixed startup cost (context, skill loads, file reads) — under-batching
is the expensive failure.

**Batch together** (single RED-GREEN cycle):

- Behaviors whose implementations land in the same module or file set — even when their tests fail
  for different structural reasons
- Edge cases and variants of the same behavior (empty input, whitespace, format variants)
- Validation rules for the same field or data type

**Keep separate** (distinct RED-GREEN cycles):

- Behaviors touching different modules or subsystems
- Anything where a single GREEN implementation would be too large to reason about or verify as one
  diff

**Rule of thumb:** group by where the implementation lands, not by why the tests fail. "Different
failure modes" or "could ship independently" are never reasons to split behaviors that live in the
same files.

## Parallel Waves: Independent Groups Run Concurrently

Batching decides what shares a cycle; **waves decide which cycles run at the same time.** Behavior
groups that are independent — neither consumes anything the other introduces (no new function, type,
or module from one used by the other) and their test files and implementation areas are disjoint —
form one wave: one `tdd-cycle` per group, all dispatched in a **single parallel message**. A group
that consumes another group's output runs in a later wave, after the producer's cycle is verified —
its code is on disk; commits wait until after REFACTOR.

Independence is judged from the plan's behavior list alone — never by reading files (the same rule
that governs batching). Unsure → serialize; a wasted wave costs one dispatch round, while two agents
editing the same file costs a corrupted cycle.

Wave mechanics (full loop in `references/orchestration-flow.md`):

- Multi-group wave prompts carry the PARALLEL WAVE notice: each agent stays inside its group's files
  and skips its own full-suite run.
- Verification: each cycle's TEST_COMMAND, then FULL_SUITE_COMMAND **once per wave**.
- No commits mid-loop: commits stay serial and per-cycle — one commit per cycle, tests and
  implementation together — but happen only in the COMMIT phase after REFACTOR; never interleave two
  cycles' files in one commit.
- Guards (`tdd-cycle-active`, per-agent `tdd-red-phase.<agent_id>` read markers) are cleared only
  after every agent in the wave has returned.
- One STUCK or TEST_FLAWED cycle never blocks the wave's PASSED cycles — verify those first, then
  surface the failure; the PASSED cycles commit with the rest after REFACTOR.

Serializing independent groups wastes wall-clock time the same way splitting cohesive behaviors
wastes dispatches; parallelizing dependent ones hands an agent a GREEN phase whose prerequisite code
doesn't exist yet. Both are wave-planning failures.

## Orchestration Flow

For the detailed entry-point logic, RED-GREEN-REFACTOR loop pseudocode, and phase data contracts,
see `references/orchestration-flow.md`.

## Red-Green-Refactor

### RED — Write Failing Tests

The `tdd-cycle` agent's RED phase writes tests for one behavior group — a single behavior or a
cohesive batch (see Batching section above). Each individual test still covers one thing; edge cases
and error paths belong in the group's tests.

### Verify RED — Inspect FAILURE_OUTPUT

**MANDATORY. Never skip.** The agent runs both phases internally, so you cannot re-run the failing
state. `FAILURE_OUTPUT` is the evidence that substitutes for it: the failure message must be
expected, and it must fail because the feature is missing (not typos).

The agent NEVER commits — and neither do you until the COMMIT phase after REFACTOR. Non-PASSED
statuses (PASSED_UNEXPECTEDLY, STUCK, TEST_FLAWED) are handled per
`references/orchestration-flow.md` step 3.

### GREEN — Minimal Code

The `tdd-cycle` agent's GREEN phase writes the simplest code to pass the test.

### Verify GREEN — Watch It Pass

**MANDATORY. Run TEST_COMMAND and FULL_SUITE_COMMAND yourself** — do not rely solely on tdd-cycle's
report.

Confirm:

- Specific test passes
- Full test suite passes
- Output pristine (no errors, warnings)

**Test fails?** Fix code, not test.

**Other tests fail?** Fix regressions now.

### REFACTOR — Clean Up (after the last cycle, before any commit)

REFACTOR runs **once** after all RED-GREEN cycles complete, not per-cycle — and **before any
commit**. Nothing is committed until REFACTOR finishes, so every commit contains the cleaned-up
code; there is no separate refactor commit.

- **< 50 insertions** across this invocation's files → skip REFACTOR, go to Commit.
- **≥ 50 insertions** → run the distill-and-mend sequence (`references/orchestration-flow.md` steps
  10–12).

The heavier review lenses (`vet-code`, `vet-test`, `bug-scanner`) are deliberately absent: they run
in the pre-push `/preflight` pass. REFACTOR's job is shape and comment hygiene on freshly written
code, so later tasks don't inherit — and imitate — crust.

### Commit — Last Phase

Commits come after REFACTOR, never before or during the loop.

**Approval gate** — the skill prescribes _when_ to commit; the user's approval authorizes _that_ it
happens. A **plan task** is a numbered task from a plan the user approved this session; everything
else is **ad hoc**:

- **Plan task or autocommit active** — commit proceeds without pausing (approval already granted).
- **Ad hoc** — list each cycle's test files and implementation files in commit order. **Stop — no
  `git commit` in this turn.** Wait for the user's next message with explicit approval. "Present and
  proceed" in a single turn is committing without approval.

Then load `Skill(write-commit)` and commit cycle by cycle — one commit per cycle (staging rules in
`references/orchestration-flow.md`).

### Repeat

Next wave. One vertical slice (or cohesive batch) per cycle; independent cycles share a wave.

## When Stuck

| Problem                        | Solution                                                |
| ------------------------------ | ------------------------------------------------------- |
| tdd-cycle can't find API       | Add type stubs or update `__init__.py` exports.         |
| tdd-cycle hits circuit breaker | Review test assumptions. Consider adjusting test scope. |
