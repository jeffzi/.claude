---
name: tdd
description: >
  Use when implementing any feature, behavior change, or bug fix in a project with a test suite.
  Also use when asked to follow TDD or invoked via /tdd. Use when you think "I'll add tests later"
  — that's rationalization. Not for projects without a test suite.
argument-hint: "[feature or behavior to implement]"
---

# Test-Driven Development (TDD)

**Feature / Behavior:** $ARGUMENTS

## Table of Contents

- [Overview](#overview)
- [When to Use](#when-to-use)
- [Plans and TDD](#plans-and-tdd)
- [The Iron Law](#the-iron-law)
- [Architecture: Context-Isolated Subagents](#architecture-context-isolated-subagents)
- [Language Skill Dispatch](#language-skill-dispatch)
- [Batching: Cohesive vs. Unrelated](#batching-cohesive-vs-unrelated)
- [Orchestration Flow](#orchestration-flow)
- [Red-Green-Refactor](#red-green-refactor)
- [Circuit Breaker](#circuit-breaker)
- [Example: Bug Fix](#example-bug-fix)
- [Verification Checklist](#verification-checklist)
- [When Stuck](#when-stuck)
- [Debugging Integration](#debugging-integration)

## Overview

Write the test first. Watch it fail. Write minimal code to pass. Context-isolated via subagents.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## When to Use

**Always:**

- New features and behavior changes
- Bug fixes
- Refactoring with behavior implications

**Exceptions (ask your human partner):**

- Throwaway prototypes
- Generated code
- Configuration files

Thinking "skip TDD just this once"? Stop. That's rationalization.

## Plans and TDD

**Before creating any plan, load `Skill(write-plan)`.** Always. No exceptions.

When the project has a test suite, plans describe **behaviors to implement** plus the files they
touch (`write-plan`'s Files section) — never line numbers, inline code, or prescribed
implementations. Those details compromise the agents' context isolation; file paths do not (the
orchestrator hands `tdd-cycle` the test file paths anyway). Each plan task ends with **"Use `/tdd`
for implementation."** — no inline RED/GREEN steps, no test assertions, no implementation code.

When the project has no test suite, plans describe implementation directly (files, approach,
specific changes) — TDD constraints don't apply.

**Good:** "Modify `hud/prepare.lua`: accept hud.duration as a positive number, default 0.5. Use
`/tdd` for implementation." **Bad:** "Update prepare.lua:614, validate as positive number." —
prescribes implementation.

## The Iron Law

No production code without a failing test first. See `references/philosophy.md` for the full
principles, rationalizations table, and red flags checklist.

## Architecture: Context-Isolated Subagents

Context isolation prevents the LLM from designing tests around planned implementation.

| Phase     | Agent                            | Can see (Phase 1 / Phase 2)                      | Cannot see/modify                          |
| --------- | -------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| RED-GREEN | `tdd-cycle`                      | Phase 1: tests, stubs, public API / Phase 2: all | Phase 1: impl source / Phase 2: test files |
| REFACTOR  | 2 parallel tracks (if ≥50 lines) | Everything                                       | N/A (see REFACTOR section)                 |

### Mandatory Entry Point

**NEVER dispatch `tdd-cycle` directly.** This skill is the orchestrator — without it, no phase
verification, no circuit breaker, no structured data passing.

## Language Skill Dispatch

Before the **first** RED-GREEN cycle, load `Skill(test-core)`. That hub contains the universal
testing principles (AAA, behavior-not-implementation, parametrize-over-loops, mocking anti-patterns)
that every `tdd-cycle` invocation must respect.

The language dispatch table lives in `rules/skill-loading.md` (already in session context) — look up
the test file extension under **Language Dispatch for test-\* and code-\*** to find the matching
`test-{lang}` and `code-{lang}` skills. The `tdd-cycle` agent loads them in its RED and GREEN phases
respectively. If the extension has no row, note "no matching skill" and proceed with `test-core`
principles alone.

`tdd-cycle` resolves TEST_COMMAND and FULL_SUITE_COMMAND during its RED phase — the orchestrator
uses these for independent GREEN verification.

## Batching: Cohesive vs. Unrelated

Each RED-GREEN cycle covers a **behavior group** — one behavior or a cohesive batch of related
behaviors that share the same implementation area.

**Batch together** (single RED-GREEN cycle):

- Edge cases of the same behavior (empty input, whitespace, too-long, special chars)
- Closely related micro-features that touch the same function/module
- Validation rules for the same field or data type
- Format variants of the same operation (CSV, JSON, YAML output)

**Keep separate** (distinct RED-GREEN cycles):

- Behaviors touching different modules or subsystems
- Features that could ship independently
- Behaviors with different failure modes or error paths
- Anything where a single GREEN implementation would be too large to reason about

**Rule of thumb:** If all the tests will fail for the same structural reason (missing function,
missing branch, missing parameter), they belong in one batch. If they'd fail for different reasons,
they're separate cycles.

## Orchestration Flow

For the detailed entry-point logic, RED-GREEN-REFACTOR loop pseudocode, and phase data contracts,
see `references/orchestration-flow.md`.

## Red-Green-Refactor

### RED — Write Failing Tests

The `tdd-cycle` agent's RED phase writes tests for one behavior group — a single behavior or a
cohesive batch (see Batching section above). Each individual test still covers one thing.

**Good** — Three tests, one RED-GREEN cycle (all fail because CatalogEntry doesn't exist yet):

```python
# Cohesive batch: all test CatalogEntry validation (same model, same structural reason)
def test_catalog_entry_parses_valid_section():
    entry = CatalogEntry(**valid_catalog)
    assert entry.name == "My App"

def test_catalog_entry_rejects_missing_field():
    with pytest.raises(ValidationError):
        CatalogEntry(**{k: v for k, v in valid_catalog.items() if k != "name"})

def test_catalog_entry_rejects_invalid_type():
    with pytest.raises(ValidationError):
        CatalogEntry(**{**valid_catalog, "type": "invalid"})
```

**Bad** — Same model, same failure reason — splitting wastes time without improving isolation:

```python
# One test per RED-GREEN cycle for the same model — 3 agent dispatches for no benefit
# Cycle 1: RED → GREEN for test_catalog_entry_parses_valid_section
# Cycle 2: RED → GREEN for test_catalog_entry_rejects_missing_field
# Cycle 3: RED → GREEN for test_catalog_entry_rejects_invalid_type
```

**Requirements:**

- One behavior group per cycle (see Batching section)
- Each individual test covers one thing — clear name describing behavior
- Real code (no mocks unless unavoidable)

### Verify RED — Inspect FAILURE_OUTPUT

**MANDATORY. Never skip.** The agent runs both phases internally, so you cannot re-run the failing
state. `FAILURE_OUTPUT` is the evidence that substitutes for it: the failure message must be
expected, and it must fail because the feature is missing (not typos).

The agent NEVER commits — you commit after verification passes, in TDD order (test files first, then
implementation files; see the orchestration flow). Never ask the agent for a commit or instruct it
to make one.

**`STATUS: PASSED_UNEXPECTEDLY`?** Behavior already exists. Report to user and ask: skip or revise
scope?

**`STATUS: STUCK + PHASE: RED`?** Test writing failed. Report diagnostics to user.

### GREEN — Minimal Code

The `tdd-cycle` agent's GREEN phase writes simplest code to pass the test.

**Good** — Just enough to pass:

```typescript
async function retryOperation<T>(fn: () => Promise<T>): Promise<T> {
  for (let i = 0; i < 3; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i === 2) throw e;
    }
  }
  throw new Error('unreachable');
}
```

**Bad** — Over-engineered:

```typescript
async function retryOperation<T>(
  fn: () => Promise<T>,
  options?: {
    maxRetries?: number;
    backoff?: 'linear' | 'exponential';
    onRetry?: (attempt: number) => void;
  }
): Promise<T> {
  // YAGNI
}
```

Don't add features, refactor other code, or "improve" beyond the test.

### Verify GREEN — Watch It Pass

**MANDATORY. Run TEST_COMMAND and FULL_SUITE_COMMAND yourself** — do not rely solely on tdd-cycle's
report.

Confirm:

- Specific test passes
- Full test suite passes
- Output pristine (no errors, warnings)

**Test fails?** Fix code, not test.

**Other tests fail?** Fix regressions now.

### REFACTOR — Clean Up (after the last cycle)

REFACTOR runs **once** after all RED-GREEN cycles complete, not per-cycle.

Compute total insertions across all files modified/added during this `/tdd` invocation using
`git diff --stat`. If total insertions are **< 50 lines**, skip REFACTOR entirely.

If **≥ 50 lines**, split changed files into impl and test files. Run two tracks in parallel:

- **Impl track:** dispatch `code-distiller` on impl files; then dispatch `subagent_type: vet-code`
  **and** `subagent_type: vet-comments` on the result, in parallel
- **Test track:** dispatch `code-distiller` on test files; then dispatch `subagent_type: vet-test`
  **and** `subagent_type: vet-comments` on the result, in parallel

`vet-comments` runs on both tracks because distillation rewrites the code its comments describe —
restatement, stale anchors, and doc-comment gaps surface only after the shape settles.

Do NOT set model on any reviewer dispatch — the agents define their own. They load `code-core` /
`test-core` and the language leaf inside their own context, so pass no skill in the prompt.

The reviewers are read-only: they return `### Finding N` blocks and change nothing. Apply their
findings in the main context, then re-run FULL_SUITE_COMMAND if either track applied changes.

### Repeat

Next behavior group. One vertical slice (or cohesive batch) per cycle.

## Circuit Breaker

### Tier 1: After 3 failed GREEN attempts

The `tdd-cycle` agent's GREEN phase switches to a fundamentally different approach (different
algorithm, alternative API, restructured logic).

### Tier 2: After 5 total GREEN failures

Agent reports STUCK with diagnostics. Orchestrator presents to user with options:

- Adjust the test (maybe it's too strict)
- Try manual implementation
- Skip this behavior for now

## Example: Bug Fix

**Bug:** Empty email accepted

**RED** (via tdd-cycle agent, RED phase)

```typescript
test('rejects empty email', async () => {
  const result = await submitForm({ email: '' });
  expect(result.error).toBe('Email required');
});
```

### Verify RED

```text
FAIL: expected 'Email required', got undefined
```

**GREEN** (via tdd-cycle agent, GREEN phase)

```typescript
function submitForm(data: FormData) {
  if (!data.email?.trim()) {
    return { error: 'Email required' };
  }
  // ...
}
```

### Verify GREEN

```text
PASS
```

**REFACTOR** — Run code-distiller + vet tracks if ≥50 lines changed. Extract validation for multiple
fields if needed.

## Verification Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing (confirmed via FAILURE_OUTPUT from tdd-cycle)
- [ ] Each test failed for expected reason (feature missing, not typo)
- [ ] Committed each cycle yourself in TDD order (tests first, then implementation) — the agent
      never commits
- [ ] Wrote minimal code to pass each test (via tdd-cycle agent)
- [ ] All tests pass
- [ ] Output pristine (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Showed test output proving pass (not "should pass" — actual output)
- [ ] Edge cases and errors covered
- [ ] REFACTOR ran (if ≥50 lines changed) or skipped with reason logged

Can't check all boxes? You skipped TDD. Start over.

## When Stuck

| Problem                        | Solution                                                             |
| ------------------------------ | -------------------------------------------------------------------- |
| Don't know how to test         | Write wished-for API. Write assertion first. Ask your human partner. |
| Test too complicated           | Design too complicated. Simplify interface.                          |
| Must mock everything           | Code too coupled. Use dependency injection.                          |
| Test setup huge                | Extract helpers. Still complex? Simplify design.                     |
| tdd-cycle can't find API       | Add type stubs or update `__init__.py` exports.                      |
| tdd-cycle hits circuit breaker | Review test assumptions. Consider adjusting test scope.              |

## Debugging Integration

Bug discovered mid-session? Write a failing test via tdd-cycle before fixing. For standalone bug
reports (unknown root cause), use `/fix` first — it investigates, then drives TDD.

## Pressure Testing

RED phase failures this skill was designed to address:

- Agents writing implementation first, then retrofitting tests
- Batching unrelated behaviors into one RED-GREEN cycle to "save time"
- Orchestrators reading source files during Phase 1 to "understand the API"
- Agents dispatching tdd-cycle directly, bypassing the orchestrator

See `references/philosophy.md` for the full rationalization table and red flags.
