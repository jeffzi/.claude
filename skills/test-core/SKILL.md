---
name: test-core
description: >
  Use when writing or reviewing tests in any language. Covers test behavior vs. implementation, AAA
  structure, test desiderata, merge/redundancy rules, false-coverage detection, parametrization, and
  mocking anti-patterns. Not for TDD orchestration — use `Skill(tdd)`.
user-invocable: false
model: sonnet
effort: medium
---

# Test Core — Cross-Language Testing Principles

**Core principle:** Test behavior, not implementation. A refactor that preserves observable behavior
should never break a test.

**Also apply** the language-specific skill for the file(s) you are working on. This hub loads it for
you — see [Dispatch](#dispatch).

## Dispatch

`test-core` is the entry point for all test work. Language skills are leaves, not parents — they are
loaded _from_ here, never the other way around.

**Process:**

1. Read the target file's extension.
2. Look up the extension in `rules/skill-loading.md` → **Language Dispatch for test-\* and code-\***
   (already in your session context — no extra load).
3. Load the matching **Test skill** via `Skill(test-{lang})`.
4. That base skill's **Domain Skill Detection** section scans imports and loads any overlay skills
   automatically (e.g. `test-py` detects `import polars` → loads `test-polars`).
5. If the extension has no row in the table: check for `Skill(test-*)` via Glob. If none matches,
   note "no matching test skill" and proceed using project conventions.

Do not pre-compute overlays. Do not maintain an inline extension table here — the single source of
truth is the rules file.

## The Principles

### 1. Arrange-Act-Assert

Every test function has three distinct phases, in order:

1. **Arrange** — set up preconditions and inputs
2. **Act** — execute the behavior under test (single action)
3. **Assert** — verify the expected outcome

No logic between phases. No assertions in Arrange. One Act per test. "And" in the test name? Split
it.

### 2. Test Behavior, Not Implementation

Assert what the code **does** (outputs, return values, side effects, state changes), not **how** it
does it internally.

| Fragile (implementation-coupled)               | Resilient (behavior-focused)                         |
| ---------------------------------------------- | ---------------------------------------------------- |
| Assert internal method was called              | Assert observable output or state changed            |
| Mock private helpers or internal collaborators | Mock only at system boundaries (I/O, network, clock) |
| Verify exact call count/order on mocks         | Verify end result                                    |
| Assert internal data structure shape           | Assert public API contract                           |
| Snapshot an entire object for one field        | Assert only the relevant field(s)                    |
| Import and test private functions directly     | Drive coverage through the public API                |

**Rule of thumb:** If you can change the implementation without changing the behavior, and your test
breaks, the test is coupled to implementation.

### 3. Never Test Private Functions Directly

If a private function (`_helper`, `_parse`, etc.) isn't reachable through the public API, either
it's dead code or the public API is too narrow — fix the design, don't test the internals.

```python
# BAD: testing private function directly to pad coverage
from mymodule._internals import _parse_discount_rule
assert _parse_discount_rule("15%") == 0.15

# BAD: asserting internal wiring instead of outcome
mock_engine.calculate_percentage.assert_called_once_with(0.15)

# GOOD: drives coverage through the public API, survives refactors
assert checkout.total == 85.00  # 15% discount applied to $100
```

### 4. False Coverage — Mocks That Assert Their Own Return Value

A test that mocks a collaborator and asserts the mock's own return value exercises zero real logic —
the test name says "with discount" but no discount code runs. **If removing the production code
wouldn't fail the test, the test covers nothing.**

### 5. Minimum Tests, Maximum Coverage

| Merge when                          | Keep separate when    |
| ----------------------------------- | --------------------- |
| Same code path, different inputs    | Different code paths  |
| Related edge cases (None, empty, 0) | Complex setup differs |
| Same behavior across APIs           | Tests need isolation  |

Do not test trivial behavior unless strictly necessary to traverse a code path for coverage. Even
then, traverse each trivial code path purposefully **only once** across the entire test suite.

### 6. Parametrize Over Loops

When the same code path runs with varying inputs, use the language's parametrization mechanism —
**not** a loop inside a single test function.

| Language   | Parametrization                                      |
| ---------- | ---------------------------------------------------- |
| Python     | `@pytest.mark.parametrize("a,b,expected", [...])`    |
| TypeScript | `test.each([...])` / `it.each([...])` in Vitest/Jest |
| Lua        | Loop over table driving a separate `it()` per case   |
| Swift      | `@Test(arguments: [...])` in Swift Testing           |

Loops stop at the first failure; parametrization reports each case independently and names them. A
loop over assertions inside one test is an anti-pattern — see the
[Stacked Assertions](references/anti-patterns.md#anti-pattern-6-stacked-assertions-over-varying-inputs)
anti-pattern.

### 7. Test Desiderata

Every test should satisfy these properties. The most actionable subset for code review:

| Property              | Meaning                                                    |
| --------------------- | ---------------------------------------------------------- |
| Isolated              | Same results regardless of run order                       |
| Composable            | Test dimensions of variability separately, combine results |
| Deterministic         | Same result if nothing changes                             |
| Readable              | Comprehensible, invokes motivation for the test            |
| Behavioral            | Sensitive to behavior changes, not implementation          |
| Structure-insensitive | Unaffected by structural code changes                      |
| Specific              | Failure cause is obvious                                   |

Full list: [testdesiderata.com](https://testdesiderata.com/).

### 8. Good Tests Checklist

| Quality          | Good                                | Bad                                                 |
| ---------------- | ----------------------------------- | --------------------------------------------------- |
| **Minimal**      | One thing. "and" in name? Split it. | `test('validates email and domain and whitespace')` |
| **Clear**        | Name describes behavior             | `test('test1')`                                     |
| **Shows intent** | Demonstrates desired API            | Obscures what code should do                        |

## When Adding Coverage

Adding tests to an existing feature (coverage gap-filling, not new behavior) has its own rules:

- **Never modify implementation files.** Coverage work is test-only. If the implementation needs to
  change to be testable, STOP and surface it — don't silently refactor.
- **STOP and REPORT bugs — don't work around them.** If a test reveals a bug, surface it and let the
  user decide. Do not write a test that encodes the buggy behavior as "expected," and do not tweak
  inputs to dodge the failure.
- **Maximize coverage, minimize test volume.** Parametrize across inputs that share a code path
  rather than adding separate test functions. Apply the
  [merge table](#5-minimum-tests-maximum-coverage).
- **Extend existing test files.** If the feature already has a test file, add cases there. Do not
  create `*_coverage`, `*_extra`, or similar parallel files dedicated solely to raising coverage —
  they fragment the suite and hide intent.

## Mocking Anti-Patterns

Before adding a mock, before writing a test that asserts on a mock, or before reviewing a file that
uses mocks, load `@references/anti-patterns.md`. It covers the six universal anti-patterns (testing
mock behavior, test-only methods in production, mocking without understanding, incomplete mocks,
integration-tests-as-afterthought, and stacked assertions over varying inputs) with gate functions
and fixes.

**One-line summary:** Mocks are tools to isolate, not things to test.

## Universal Rationalizations

| Excuse                                   | Reality                                                         |
| ---------------------------------------- | --------------------------------------------------------------- |
| "Too simple to test"                     | Simple code breaks. Test takes 30 seconds.                      |
| "Tests look reasonable"                  | "Reasonable" skips pairwise comparison. Apply the merge table.  |
| "AAA is implied"                         | Implicit ≠ verified. Check phase separation per test.           |
| "Each edge case deserves its own test"   | Same code path + different inputs = merge. See merge table.     |
| "I need to verify the mock was called"   | Assert the outcome, not the wiring. See behavior-vs-impl table. |
| "Testing _func directly boosts coverage" | Coverage via private imports is fake. Drive through public API. |
| "The mock returns the right value"       | That tests the mock, not the code. See false coverage note.     |
| "The linter would have caught this"      | Linters miss redundancy, naming, philosophy, structure.         |
| "Loop is cleaner than parametrize"       | Parametrize shows all cases; loop stops at first failure.       |
| "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk the checklist rule-by-rule.       |

## Red Flags

STOP and re-check if any of these are true:

- Zero violations in a non-trivial file — scan again rule-by-rule
- A test asserts on an element whose test ID ends with `-mock`
- A method is only called from test files
- Mock setup is >50% of the test body
- Test fails when you remove a mock (and the product code didn't change)
- You cannot explain, in one sentence, what behavior the test proves
- A loop inside the test body is performing the same assertion with different inputs
- A test imports from `_internals` / `_private` / other private modules

## Downstream Consumers

This skill is loaded by three callers, each using the principles for a different purpose:

| Caller     | Purpose                                                             |
| ---------- | ------------------------------------------------------------------- |
| `tdd`      | RED phase — write tests that follow these principles from the start |
| `vet-test` | Review — walk a combined checklist over every test function         |
| Direct use | Any hand-written test outside a TDD cycle                           |

Language skills (`test-py`, `test-ts`, `test-lua`, `test-swift`, overlays like `test-polars`) add
language-specific syntax and pitfalls on top — they do **not** restate these principles.
