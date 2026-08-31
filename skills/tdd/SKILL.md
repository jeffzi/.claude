---
name: tdd
description: >
  Use when implementing any feature, behavior change, or bug fix in a project with a test suite.
  Also use when asked to follow TDD or invoked via /tdd. Use when you think "I'll add tests later"
  — that's rationalization. Not for projects without a test suite. Not for bugs with unknown root
  cause — use /fix first (it investigates, then drives TDD).
argument-hint: "[feature or behavior to implement]"
---

# TDD

**Feature / Behavior:** $ARGUMENTS

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## The Iron Law

No production code without a failing test first. Wrote code before its test? Delete it — no keeping
as "reference", no adapting while writing tests, no commit-and-fix-forward; start over from a
failing test. Exceptions exist, but the user grants them — ask before skipping for throwaway
prototypes, generated code, or configuration files.

| Excuse                                                         | Reality                                                                                                   |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| "I'll orchestrate RED-GREEN-REFACTOR myself"                   | Context isolation is the entire point. Invoke `/tdd`.                                                     |
| "Plan already has RED/GREEN steps" / "Plan shows inline code"  | Plans describe behaviors, not test/impl details. Use `/tdd` for implementation.                           |
| "Each test needs its own cycle" / "I'll batch later"           | Cohesive batches belong in one cycle. Different modules = separate cycles. See Batching.                  |
| "Let me read the source first" / "I'll write test inline"      | RED agent reads what it needs. Context isolation exists for a reason.                                     |
| "Just one quick cycle, no plan needed"                         | Multi-behavior tasks need a plan. Plans describe behaviors; agents figure out how.                        |
| "I'll dispatch `tdd-cycle` directly, skip the orchestrator"    | No phase verification, no circuit breaker, no data contracts. Always go through `/tdd`.                   |
| "The workflow prescribes committing, so it's pre-approved"     | The skill prescribes _when_; the user authorizes _that_. Ad hoc → ask first.                              |
| "I'll present the message and commit in the same turn"         | Present-and-proceed is committing without approval. Stop the turn; wait for the user.                     |
| "write-commit handles approval, so the TDD gate is redundant"  | The TDD gate is the orchestrator's own rule. Loading write-commit does not replace it.                    |
| "Plan task → proceed, so I commit and list the findings after" | The grant covers verified work, not unseen findings. SURFACE gate first: findings, end turn, then commit. |

| Red flag — STOP, delete the code, start over with TDD                          |
| ------------------------------------------------------------------------------ |
| Code before test / test passes immediately / can't explain why the test failed |
| Dispatching `tdd-cycle` without invoking `/tdd` first                          |
| Orchestrator reading implementation source or writing test code directly       |
| Dispatching agents without a plan for multi-behavior tasks                     |
| Dispatching agents from plan mode instead of writing plan tasks                |
| Plan contains implementation details or inline RED/GREEN test/impl code        |

## Architecture

Context isolation prevents the LLM from designing tests around planned implementation.

| Phase     | Agent                                       | Can see (Phase 1 / Phase 2)                      | Cannot see/modify                          |
| --------- | ------------------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| RED-GREEN | `tdd-cycle`                                 | Phase 1: tests, stubs, public API / Phase 2: all | Phase 1: impl source / Phase 2: test files |
| REFACTOR  | code-distiller → vet-comments → code-mender | Everything                                       | N/A                                        |

**NEVER dispatch `tdd-cycle` directly** — this skill is the orchestrator.

## Dispatch First

The `tdd-cycle` dispatch is each cycle's first tool call — nothing to read, run, or check between
the task's behavior list and the Agent call: no Read, no Bash, no Glob, no Grep.

| Excuse                                            | Reality                                                                          |
| ------------------------------------------------- | -------------------------------------------------------------------------------- |
| "Checking TSTL markers is routing, not reading"   | You pass paths, never a language. tdd-cycle's hubs route in its own context.     |
| "A green baseline confirms the suite works first" | tdd-cycle resolves and runs the commands in RED. Your first run is Verify GREEN. |
| "I said I'd dispatch — these reads are just prep" | The announcement is not the dispatch. Any prep before the Agent call is drift.   |

**The orchestrator routes; it never reads target files.** Prompts carry behavior descriptions and
file paths; `tdd-cycle` loads the test/code hubs and resolves TEST_COMMAND and FULL_SUITE_COMMAND in
RED; the orchestrator loads no testing or coding skills.

## Batching

Each cycle covers a **behavior group** — behaviors sharing one implementation area; under-batching
is the expensive failure: every dispatch re-pays fixed startup cost.

| Batch together (one cycle)                                                                                     | Keep separate (distinct cycles)                    |
| -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Behaviors landing in the same module or file set — even when their tests fail for different structural reasons | Behaviors touching different modules or subsystems |
| Edge cases and variants of the same behavior                                                                   | A GREEN diff too large to reason about as one      |
| Validation rules for the same field or data type                                                               |                                                    |

**Rule of thumb:** group by where the implementation lands, not by why the tests fail. "Different
failure modes" or "could ship independently" are never reasons to split behaviors that live in the
same files.

## Parallel Waves

Independent groups — neither consumes anything the other introduces; test files and implementation
areas disjoint — form one wave: one `tdd-cycle` per group in a single parallel message; dependent
groups wait for later waves. Independence is judged from the plan's behavior list alone — never by
reading files (unsure → serialize). Serializing independent groups wastes wall-clock time;
parallelizing dependent ones hands an agent a GREEN phase missing its prerequisites.

## The Loop

Run the loop per `references/orchestration-flow.md`. Non-negotiables:

- **Verify RED — MANDATORY, never skip.** Inspect FAILURE_OUTPUT: expected failure, feature missing,
  not typos.
- **Verify GREEN — MANDATORY.** Run TEST_COMMAND and FULL_SUITE_COMMAND yourself — never rely solely
  on the agent's report. Test fails → fix code, not test.
- **REFACTOR once**, after all cycles, before any commit: < 50 insertions → skip; ≥ 50 →
  distill-and-mend (steps 10–12).
- **Surface before commit.** Any open item — unconfirmed finding, flaky test, "unrelated" issue — is
  shown to the user and the turn ends before any commit (orchestration-flow § SURFACE).
- **Commit last.** Plan task or autocommit → proceed; ad hoc → list each cycle's files and stop for
  explicit approval. Then `Skill(write-commit)` — one commit per cycle, tests and implementation
  together; agents never commit.

## When Stuck

| Problem                        | Solution                                                |
| ------------------------------ | ------------------------------------------------------- |
| tdd-cycle can't find API       | Add type stubs or update `__init__.py` exports.         |
| tdd-cycle hits circuit breaker | Review test assumptions. Consider adjusting test scope. |
