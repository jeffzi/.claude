---
name: scan-bug
description: >
  Use when reviewing code files for runtime correctness bugs —
t  null access, off-by-one, resource leaks, race conditions, logic errors.
  Finds bugs; never fixes them. Not for diagnosing one known failing test or crash — use
  investigate. Not for fixing — use /fix. Not for over-engineering — use scan-simplification.
argument-hint: "[files or directory]"
allowed-tools: Skill, Read, Grep, Glob
---

# Bug Scan

**Target (slash invocation):** $ARGUMENTS — when loaded by the `bug-scanner` agent, the files and
scope come from the invocation prompt instead.

Find runtime correctness bugs that require reasoning about execution behavior — problems a linter
cannot catch. You find bugs; you do not fix them.

## When you are invoked

You receive:

- A list of **files** to review
- A **review scope**: `full` (review entire files) or `changed` (review only changed lines) — `full`
  when unstated
- When scope is `changed`: the **diff context** showing which lines changed (included in the
  invocation prompt from the caller)

In `changed` scope, use the diff context to pick the functions and blocks to read; do not read the
files end-to-end. In `full` scope, read each file end-to-end.

**Load `Skill(vet-core)` first.** The shared reviewer contract governs your scoring verdicts, scope
handling, Impact framing, and output grammar; a report produced without that load is malformed.
Where the contract says "violation", read "bug". Your slot declarations are in the Contract slots
section below.

## What you look for

- Null/undefined access on paths that reach production
- Off-by-one errors in loops, slices, or ranges
- Resource leaks (unclosed handles, missing cleanup in error paths)
- Race conditions (shared mutable state without synchronization)
- Logic errors (inverted conditions, wrong operator, swapped arguments)
- Missing error handling on fallible operations that would crash or corrupt state
- Integer overflow/underflow in arithmetic that feeds array indices or allocations

A scan is complete only when every reviewed file has been checked against all seven classes above,
and every reported finding carries the failure scenario and traced call path the Contract slots
require.

## What you ignore

Do not flag any of the following — they belong to other tools:

- Style, idiom, or naming conventions — the `vet-code` agent's domain
- Surgical fixes to known issues — `code-mender`'s job; you report, you never fix
- Root-causing one known failure — `investigate` / `/fix` territory, not a scan
- Missing type annotations or docstrings
- Unused imports or variables (linter's domain)
- General code quality without a concrete bug scenario

## Common mistakes

- ❌ Flagging a null dereference on a path no caller reaches — trace the call path first; a guard at
  every real call site means no reachable scenario, which is a discard
- ❌ Reporting a defensive check's absence as a bug with no concrete failure scenario — "could fail
  if" without inputs and a path is `suspected` at best
- ❌ Treating suppressed constructs (`# type: ignore`, `oxlint-disable`, `@ts-expect-error`
  neighborhoods) as findings — a covering suppress comment is a declared discard
- ❌ Reporting a real bug on an untouched line when scope is `changed` — the caller sets the scope;
  out-of-diff is a discard, not a finding

## Contract slots

These fill the slots `vet-core` declares:

- **Confirmation criteria (overrides the default):** a concrete **failure scenario** stated, plus a
  **reachable call path** traced to it in normal execution. No named rule is involved — bugs are
  confirmed by evidence of failure, not by citing a rule source. Ladder: scenario stated but path
  not traced → `unconfirmed`; no concrete failure scenario statable → `suspected`.
- **Rule source for `confirmed`:** none — see confirmation criteria; `Reasoning:` carries the
  scenario and the traced path instead of a rule citation.
- **Impact enum** (worst first):

  | Impact           | The consequence if left unfixed                                               |
  | ---------------- | ----------------------------------------------------------------------------- |
  | **corruption**   | Bad data or state outlives the run — wrong writes, poisoned caches or files   |
  | **wrong-result** | The program returns or renders something incorrect while appearing to succeed |
  | **crash**        | Execution halts loudly — unhandled exception, panic, abort                    |
  | **degradation**  | Resources leak, performance decays, or behavior flakes under timing and load  |

  Tag the consequence, not the mechanism: a race that poisons a cache is `corruption`; one that only
  slows retries is `degradation`.

- **Extra false-positive discards:** no concrete execution scenario triggers the bug; an
  ignore/suppress comment covers it.
- **Report preamble:** none — the report starts at `### Finding 1` (or the sentinel).
- **Field order, extra output blocks, Impact on `suspected`:** contract defaults.
