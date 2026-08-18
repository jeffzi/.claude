---
name: test-core
description: >
  Use when writing or reviewing tests in any language. Covers test behavior vs. implementation, AAA
  structure, merge/redundancy rules, false-coverage detection, parametrization, and mocking
  anti-patterns. Not for TDD orchestration — use `Skill(tdd)`.
user-invocable: false
---

# Test Core — Cross-Language Testing Principles

**Core principle:** Test behavior, not implementation. A refactor that preserves observable behavior
should never break a test.

## Dispatch

**Process:**

1. Read the target file's extension.
2. Look up the extension in `rules/skill-loading.md` → **Language Dispatch for test-\* and code-\***
   (already in your session context — no extra load).
3. Load the matching **Test skill** via `Skill(test-{lang})`.
4. That base skill's **Domain Skill Detection** section scans imports and loads any overlay skills
   automatically (e.g. `test-py` detects `import polars` → loads `test-polars`).
5. If the extension has no row in the table: check for `Skill(test-*)` via Glob. If none matches,
   note "no matching test skill" and proceed using project conventions.

Do not pre-compute overlays.

## The Principles

### 1. Arrange-Act-Assert

Every test function has three distinct phases, in order:

1. **Arrange** — set up preconditions and inputs
2. **Act** — execute the behavior under test (single action)
3. **Assert** — verify the expected outcome

No logic between phases. No assertions in Arrange. One Act per test. "And" in the test name? Split
it. Name the behavior the test proves, never an ordinal (`test1`). Separate phases with a blank
line, not with comments — `// Arrange`, `// Act`, `// Assert` labels restate what the code structure
already shows. Remove bare labels entirely; strip the prefix from comments that carry a real
explanation.

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

Every test must be **isolated** (same result regardless of run order) and **deterministic** (same
result if nothing changes).

### 6. Parametrize Over Loops

When the same code path runs with varying inputs, use the language's parametrization mechanism —
**not** a loop inside a single test function.

Rationale and the parametrized fix per language:
[Stacked Assertions](references/anti-patterns.md#anti-pattern-6-stacked-assertions-over-varying-inputs).

### 7. Project Conventions Bind Like These Principles

The project's CLAUDE.md (and files it imports, such as AGENTS.md) may state its own testing
conventions — fixture layout, naming patterns, forbidden helpers, required markers. Where present,
they join these principles with equal force: writing tests, follow them; reviewing tests, cite them
exactly like a skill rule (`CLAUDE.md: "<quoted convention>"`). A stated project convention is never
a "style preference" — the project already made that decision. Only imperative rules about test
content qualify: command references and build instructions are documentation, not conventions.

## When Adding Coverage

Adding tests to an existing feature (coverage gap-filling, not new behavior) has its own rules:

- **Never modify implementation files.** Coverage work is test-only. If the implementation needs to
  change to be testable, STOP and surface it — don't silently refactor.
- **STOP and REPORT bugs — don't work around them.** If a test reveals a bug, surface it and let the
  user decide. Do not write a test that encodes the buggy behavior as "expected," and do not tweak
  inputs to dodge the failure.
- **Apply the [merge table](#5-minimum-tests-maximum-coverage)** before adding a test function.
- **Extend existing test files.** If the feature already has a test file, add cases there. Do not
  create `*_coverage`, `*_extra`, or similar parallel files dedicated solely to raising coverage —
  they fragment the suite and hide intent.

## Mocking Anti-Patterns

Before adding a mock, before writing a test that asserts on a mock, or before reviewing a file that
uses mocks, load `references/anti-patterns.md`. It covers the six universal mocking anti-patterns
with gate functions and fixes.

**One-line summary:** Mocks are tools to isolate, not things to test.

## Universal Rationalizations

| Excuse                                   | Reality                                                         |
| ---------------------------------------- | --------------------------------------------------------------- |
| "Too simple to test"                     | Simple code breaks. Test takes 30 seconds.                      |
| "Tests look reasonable"                  | "Reasonable" skips pairwise comparison. Apply the merge table.  |
| "AAA is implied"                         | Implicit ≠ verified. Check phase separation per test.           |
| "AAA comments help readability"          | A blank line separates phases; the label restates the obvious.  |
| "Each edge case deserves its own test"   | Same code path + different inputs = merge. See merge table.     |
| "I need to verify the mock was called"   | Assert the outcome, not the wiring. See behavior-vs-impl table. |
| "Testing _func directly boosts coverage" | Coverage via private imports is fake. Drive through public API. |
| "The mock returns the right value"       | That tests the mock, not the code. See false coverage note.     |
| "The linter would have caught this"      | Linters miss redundancy, naming, philosophy, structure.         |
| "Loop is cleaner than parametrize"       | Parametrize shows all cases; loop stops at first failure.       |
| "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk the checklist rule-by-rule.       |

## Red Flags

STOP and re-check if any of these are true:

- A test asserts on an element whose test ID ends with `-mock`
- A method is only called from test files
- Mock setup is >50% of the test body
- Test fails when you remove a mock (and the product code didn't change)
- You cannot explain, in one sentence, what behavior the test proves
- A loop inside the test body is performing the same assertion with different inputs
- A test imports from `_internals` / `_private` / other private modules
- A test has `// Arrange`, `// Act`, or `// Assert` phase-label comments
