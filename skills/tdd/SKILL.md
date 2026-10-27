---
name: tdd
description: >
  Use when a change adds or alters logic (a condition, loop, parsing, a computed value) in a project
  with a test suite, when asked to follow TDD, or when invoked via /tdd. Use when you think "I'll
  add tests later" — that's rationalization. Not for changes with no logic (configuration, wording,
  prose, a renamed or moved symbol, turning on a dependency's feature): edit those directly. Not
  for projects without a test suite. Not for bugs with unknown root cause — use /fix first.
argument-hint: "[feature or behavior to implement]"
---

# TDD

**Feature / Behavior:** $ARGUMENTS

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## The Iron Law

No logic without a failing test first. Wrote logic before its test? Delete it — no keeping as
"reference", no adapting while writing tests, no commit-and-fix-forward; start over from a failing
test. Only the user can waive this, for throwaway prototypes or generated code.

Logic is what `Skill(test-core)` › Test What the Project Computes says gets a test. A change with
none — configuration, wording, prose, turning on a feature a dependency provides — is outside the
law, not an exception to it: it needs no test and no grant. Edit it, verify by running the suite or
the tool once, and report `no test: <case>`. Logic found in a configuration file (a loop, a
conditional, cleanup, parsing) moves to a script and is tested there.

## Choose the Path

Pick the path once, from the change's description, before any dispatch or file read:

| Change                                                                                     | Path                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| No logic (`test-core` › Test What the Project Computes)                                    | Edit directly. Run the tool or the suite once. Report `no test: <case>`. An existing test that pins old wording is narrowed to the computed parts; one that pins a dependency's behavior is deleted.                                       |
| Behavior-preserving: rename, move, extract, merge duplicates                               | Edit directly. The existing suite is the gate and stays green; test edits only follow moved names.                                                                                                                                         |
| Logic, in conversation                                                                     | **Inline test-first.** Load `Skill(test-core)`, write the failing test, run it and read why it fails, implement, run the suite. When the test runs and reads would flood the main context, a fork (`subagent_type: "fork"`) does the same. |
| Logic in a plan task whose **Implementation** line says `/tdd`, or several behavior groups | The agent loop: load `references/orchestration-flow.md` before anything else and follow it.                                                                                                                                                |

A change mixing logic and no-logic parts tests the logic only.

| Excuse                                                                    | Reality                                                                                                         |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| "/tdd was invoked, so it dispatches `tdd-cycle`"                          | Invoking /tdd asks for TDD, not for agents. The table picks the path.                                           |
| "One behavior, but an isolated agent is safer"                            | Isolation pays when the brief is written down, in a plan task. In conversation it costs a briefing and minutes. |
| "There are tests here, so it needs a red: a feature, a message, a rename" | Only logic an accidental edit could break has a red worth watching. Trivial wiring and wording get none.        |
| "Inline test-first is not real TDD"                                       | Watching the test fail is the TDD. Who writes it is a cost choice.                                              |

| Red flag — STOP, delete the code, start over with a failing test                    |
| ----------------------------------------------------------------------------------- |
| Logic written before its test / test passes immediately / can't explain the failure |
| Dispatching `tdd-cycle` without loading `references/orchestration-flow.md` first    |

**NEVER dispatch `tdd-cycle` directly** — the agent loop in `references/orchestration-flow.md` is
its orchestrator.

## When Stuck

| Problem                        | Solution                                                |
| ------------------------------ | ------------------------------------------------------- |
| tdd-cycle can't find API       | Add type stubs or update `__init__.py` exports.         |
| tdd-cycle hits circuit breaker | Review test assumptions. Consider adjusting test scope. |
