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
should never break a test. Violating the letter of these rules is violating the spirit of the rules.

## Dispatch

**Process:**

1. Read the target file's extension.
2. Find its row in `rules/skill-loading.md` → **Language Dispatch for test-\* and code-\*** (read
   that file if it is not already in your context).
3. Load the matching **Test skill** via `Skill(test-{lang})`.
4. That skill's **Domain Skill Detection** section loads overlays automatically (`test-py` sees
   `import polars` → loads `test-polars`). Do not pre-compute overlays.
5. No row for the extension → check for `Skill(test-*)` via Glob; if none matches, note "no matching
   test skill" and proceed using project conventions.

## The Principles

### 1. Arrange-Act-Assert

Every test function has three distinct phases, in order:

1. **Arrange** — set up preconditions and inputs
2. **Act** — execute the behavior under test (single action)
3. **Assert** — verify the expected outcome

No logic between phases. No assertions in Arrange. One Act per test. "And" in the test name? Split
it. Name the behavior the test proves, never an ordinal (`test1`). Separate phases with a blank
line, not comments — `// Arrange`, `// Act`, `// Assert` labels restate what the structure already
shows. Remove bare labels; strip the prefix from comments that carry a real explanation.

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

A test that mocks a collaborator and asserts the mock's own return value exercises zero real logic.
**If removing the production code wouldn't fail the test, the test covers nothing.**

### 5. Minimum Tests, Maximum Coverage

| Merge when                          | Keep separate when    |
| ----------------------------------- | --------------------- |
| Same code path, different inputs    | Different code paths  |
| Related edge cases (None, empty, 0) | Complex setup differs |
| Same behavior across APIs           | Tests need isolation  |

Test trivial behavior only when needed to traverse a code path for coverage — and traverse each
trivial path **once** across the entire suite, as one parametrized test per call shape (or one test
with grouped asserts per subject), never one test function per assert, and never a repeated Act
sliced across tests.

Every test is **isolated** (same result in any run order) and **deterministic** (same result if
nothing changes).

### 6. Parametrize Over Loops

When the same code path runs with varying inputs, use the language's parametrization mechanism —
**not** a loop inside a single test function.

Rationale and the parametrized fix per language:
[Stacked Assertions](references/anti-patterns.md#anti-pattern-5-stacked-assertions-over-varying-inputs).

### 7. Project Conventions Bind Like These Principles

The project's CLAUDE.md (and files it imports, such as AGENTS.md) may state testing conventions —
fixture layout, naming patterns, forbidden helpers, required markers. They bind with equal force:
follow them when writing tests, and cite them when reviewing (`CLAUDE.md: "<quoted convention>"`).
Only imperative rules about test content qualify — command references and build instructions are
documentation, not conventions.

## When Adding Coverage

Coverage gap-filling is test-only: never modify implementation files, and STOP and surface any bug a
new test reveals — don't encode buggy behavior as "expected" or tweak inputs to dodge it. Apply the
[merge table](#5-minimum-tests-maximum-coverage) before adding a test function, and extend the
feature's existing test file — never create `*_coverage`/`*_extra` parallel files.

## Mocking Anti-Patterns

Before adding a mock, asserting on a mock, reviewing a file that uses mocks, or writing or reviewing
a test that varies inputs over one code path, load `references/anti-patterns.md` — mocking
anti-patterns 1–4 and stacked assertions over varying inputs, with gate functions and fixes.

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

STOP and re-check if:

- A test asserts on an element whose test ID ends with `-mock`
- A method is only called from test files
- Mock setup is >50% of the test body
- Test fails when you remove a mock (and the product code didn't change)
- You cannot explain, in one sentence, what behavior the test proves
- A loop inside the test body performs the same assertion with different inputs
- A test imports from `_internals` / `_private` / other private modules
- A test has `// Arrange`, `// Act`, or `// Assert` phase-label comments
