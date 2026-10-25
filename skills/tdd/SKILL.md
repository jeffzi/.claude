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
prototypes or generated code.

The law covers logic `test-core` § 4a What Deserves a Test admits. A change whose only content is a
fixed configuration or prose — Taskfile task commands and arguments, `.tf` attribute values, CI or
hook YAML, dependency lists, Markdown and SKILL.md — needs no test and no grant: verify it by
running the tool once (`task --list`, `terraform validate`, the hook) and report `no test: <§ 4a
rule>`. Logic in such a file — a loop, a conditional, cleanup, parsing — moves to a script and is
tested there.

| Excuse                                                         | Reality                                                                                                                                                                                                                                                                                                        |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "I'll orchestrate RED-GREEN-REFACTOR myself"                   | Context isolation is the entire point. Invoke `/tdd`.                                                                                                                                                                                                                                                          |
| "Plan already has RED/GREEN steps" / "Plan shows inline code"  | Plans describe behaviors, not test/impl details. Use `/tdd` for implementation.                                                                                                                                                                                                                                |
| "Each test needs its own cycle" / "I'll batch later"           | Cohesive batches belong in one cycle. Different modules = separate cycles. See Batching.                                                                                                                                                                                                                       |
| "Let me read the source first" / "I'll write test inline"      | RED agent reads what it needs. Context isolation exists for a reason.                                                                                                                                                                                                                                          |
| "Just one quick cycle, no plan needed"                         | Multi-behavior tasks need a plan. Plans describe behaviors; agents figure out how.                                                                                                                                                                                                                             |
| "I'll dispatch `tdd-cycle` directly, skip the orchestrator"    | No phase verification, no circuit breaker, no data contracts. Always go through `/tdd`.                                                                                                                                                                                                                        |
| "The workflow prescribes committing, so it's pre-approved"     | The skill prescribes _when_; the user authorizes _that_. Ad hoc → ask first.                                                                                                                                                                                                                                   |
| "I'll present the message and commit in the same turn"         | Present-and-proceed is committing without approval. Stop the turn; wait for the user.                                                                                                                                                                                                                          |
| "write-commit handles approval, so the TDD gate is redundant"  | The TDD gate is the orchestrator's own rule. Loading write-commit does not replace it.                                                                                                                                                                                                                         |
| "Plan task → proceed, so I commit and list the findings after" | The grant covers verified work, not unseen findings. SURFACE gate first: findings, end turn, then commit. Only an unattended enclosing workflow (its marker holds this session's id, or the request named the plan's tasks) lifts this — then findings go to the list the caller named and the loop continues. |

| Red flag — STOP, delete the code, start over with TDD                          |
| ------------------------------------------------------------------------------ |
| Code before test / test passes immediately / can't explain why the test failed |
| Dispatching `tdd-cycle` without invoking `/tdd` first                          |
| Agent loop: orchestrator reading implementation source or writing test code    |
| Dispatching agents without a plan for multi-behavior tasks                     |
| Dispatching agents from plan mode instead of writing plan tasks                |
| Plan contains implementation details or inline RED/GREEN test/impl code        |

## Choose the Path

Pick the path once, from the change's description, before any dispatch or file read:

| Change                                                                                     | Path                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Only fixed wording, configuration or prose (`test-core` § 4a)                              | Edit directly. Run the tool or the suite once. Report `no test: <§ 4a rule>`. An existing test that pins the old wording is narrowed to the computed parts, never rewritten to the new text.                                               |
| Behavior-preserving: rename, move, extract, merge duplicates                               | Edit directly. The existing suite is the gate and stays green; test edits only follow moved names.                                                                                                                                         |
| Logic, in conversation                                                                     | **Inline test-first.** Load `Skill(test-core)`, write the failing test, run it and read why it fails, implement, run the suite. When the test runs and reads would flood the main context, a fork (`subagent_type: "fork"`) does the same. |
| Logic in a plan task whose **Implementation** line says `/tdd`, or several behavior groups | The agent loop below.                                                                                                                                                                                                                      |

The Iron Law holds on every logic path: no code before a failing test. Only the agent loop
dispatches `tdd-cycle`; Dispatch First, "the orchestrator routes", Batching, Parallel Waves and The
Loop govern that path alone.

| Excuse                                                                   | Reality                                                                                                         |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| "/tdd was invoked, so it dispatches `tdd-cycle`"                         | Invoking /tdd asks for TDD, not for agents. The table picks the path.                                           |
| "One behavior, but an isolated agent is safer"                           | Isolation pays when the brief is written down, in a plan task. In conversation it costs a briefing and minutes. |
| "A message change still needs red"                                       | Fixed wording has no test to turn red (`test-core` § 4a). Edit it and run the suite.                            |
| "A rename touches production code, so the Iron Law needs a failing test" | No behavior changes, so no test can fail first. The existing suite proves the rename.                           |
| "Inline test-first is not real TDD"                                      | Watching the test fail is the TDD. Who writes it is a cost choice.                                              |

## Architecture

Context isolation prevents the LLM from designing tests around planned implementation. It applies to
the agent loop; the other paths in Choose the Path have no orchestrator.

| Phase     | Agent                                       | Can see (Phase 1 / Phase 2)                      | Cannot see/modify                          |
| --------- | ------------------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| RED-GREEN | `tdd-cycle`                                 | Phase 1: tests, stubs, public API / Phase 2: all | Phase 1: impl source / Phase 2: test files |
| REFACTOR  | code-distiller → vet-comments → code-mender | Everything                                       | N/A                                        |

**NEVER dispatch `tdd-cycle` directly** — this skill is the orchestrator.

## Dispatch First

On the agent loop, the `tdd-cycle` dispatch is each cycle's first tool call — nothing to read, run,
or check between the task's behavior list and the Agent call: no Read, no Bash, no Glob, no Grep.

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

| Batch together (one cycle)                                                                                     | Keep separate (distinct cycles)                         |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Behaviors landing in the same module or file set — even when their tests fail for different structural reasons | Behaviors touching different modules or subsystems      |
| Edge cases and variants of the same behavior                                                                   | A GREEN diff too large to reason about as one           |
| Validation rules for the same field or data type                                                               | Behaviors with different fold targets (see Commit last) |

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
  shown to the user and the turn ends before any commit (orchestration-flow § SURFACE). Under an
  unattended enclosing workflow (`<git-dir>/execute-plan-unattended` holds this session's id) the
  items go to the list the caller named — a plan's Findings section — and the turn continues. A
  request that names tasks of a plan file to implement is such a workflow with no marker: the plan
  is the approval and its `## Findings` section is the list.
- **Commit last.** Plan task or autocommit → proceed; plan task invoked with "no-commit plan
  execution" → skip, report file lists; ad hoc → list each cycle's files and stop for explicit
  approval. Then one commit per cycle, tests and implementation together; agents never commit. A
  behavior group whose invocation carries `fixup target: <sha>` for it (one target per group when
  the invocation batches several tasks or findings) commits each of its cycles with `git commit
  --fixup=<sha>` — no `Skill(write-commit)` message; the generated `fixup! <subject>` subject passes
  the commit-message guard and the conventional-commit hook. A group without a target gets a
  `Skill(write-commit)` message. Cycles with different targets never share a commit.

## When Stuck

| Problem                        | Solution                                                |
| ------------------------------ | ------------------------------------------------------- |
| tdd-cycle can't find API       | Add type stubs or update `__init__.py` exports.         |
| tdd-cycle hits circuit breaker | Review test assumptions. Consider adjusting test scope. |
