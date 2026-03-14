---
name: test-vet
description: >
  Use when reviewing test files for redundant tests,
  AAA violations, test desiderata, and language skill
  rule violations
argument-hint: "[test file or directory]"
---

# Test Vet

## Overview

Linters catch syntactic issues. Test vet catches judgment-based violations — redundant tests, naming
drift, philosophy violations (testing implementation vs. behavior), and structural anti-patterns.

## Golden Rules

Language-agnostic. Override language-specific skills. Always verify and fix violations.

### Minimum Tests, Maximum Coverage

| Merge when                          | Keep separate when    |
| ----------------------------------- | --------------------- |
| Same code path, different inputs    | Different code paths  |
| Related edge cases (None, empty, 0) | Complex setup differs |
| Same behavior across APIs           | Tests need isolation  |

Do not test trivial behavior unless strictly necessary to traverse a code path for coverage. Even
then, traverse each trivial code path purposefully **only once** across the entire test suite.

### Arrange-Act-Assert (AAA)

Every test function follows three distinct phases, in order:

1. **Arrange** — set up preconditions and inputs
2. **Act** — execute the behavior under test (single action)
3. **Assert** — verify the expected outcome

No logic between phases. No assertions in Arrange. One Act per test.

### Test Desiderata

Every test should satisfy these properties. Subset most actionable during code review shown below;
full list at [testdesiderata.com](https://testdesiderata.com/).

| Property              | Meaning                                                    |
| --------------------- | ---------------------------------------------------------- |
| Isolated              | Same results regardless of run order                       |
| Composable            | Test dimensions of variability separately, combine results |
| Deterministic         | Same result if nothing changes                             |
| Readable              | Comprehensible, invoking motivation for the test           |
| Behavioral            | Sensitive to behavior changes, not implementation          |
| Structure-insensitive | Unaffected by structural code changes                      |
| Specific              | Failure cause is obvious                                   |

### Test Behavior, Not Implementation

Assert what the code **does** (outputs, return values, side effects, state changes), not **how** it
does it internally. A refactor that preserves behavior should never break a test.

| Fragile (implementation-coupled)               | Resilient (behavior-focused)                         |
| ---------------------------------------------- | ---------------------------------------------------- |
| Assert internal method was called              | Assert observable output or state changed            |
| Mock private helpers or internal collaborators | Mock only at system boundaries (I/O, network, clock) |
| Verify exact call count/order on mocks         | Verify end result                                    |
| Assert internal data structure shape           | Assert public API contract                           |
| Snapshot an entire object for one field        | Assert only the relevant field(s)                    |
| Import and test private functions directly     | Drive coverage through the public API                |

**Never test private functions directly.** If a private function (`_helper`, `_parse`, etc.) isn't
reachable through the public API, either it's dead code or the public API is too narrow — fix the
design, don't test the internals. Testing private functions to increase coverage creates tests that
break on every refactor and protect nothing users care about.

```python
# BAD: testing private function directly to pad coverage
from mymodule._internals import _parse_discount_rule
assert _parse_discount_rule("15%") == 0.15

# BAD: asserting internal wiring instead of outcome
mock_engine.calculate_percentage.assert_called_once_with(0.15)

# GOOD: drives coverage through the public API, survives refactors
assert checkout.total == 85.00  # 15% discount applied to $100
```

**Watch for false coverage:** A test that mocks a collaborator and asserts the mock's own return
value exercises zero real logic — the test name says "with discount" but no discount code runs. If
removing the production code wouldn't fail the test, the test covers nothing.

**Rule of thumb:** If you can change the implementation without changing the behavior, and your test
breaks, the test is coupled to implementation.

## Process

1. Detect test files from path and determine language:
   - `.py` files matching `test_*.py` or `*_test.py` → `test-py`
   - `.lua` files matching `test_*.lua` or `*_test.lua` → `test-lua`
   - `.js`/`.ts` files matching `*.test.js`, `*.spec.js`, etc. → `test-js`
2. Load the matching `test-<lang>` skill (e.g., `test-py`, `test-lua`). If no `test-<lang>` skill
   exists, fall back to `code-<lang>` (e.g., `code-lua`)
3. If the skill cross-references a `code-<lang>` skill (e.g., `test-py` says "Also apply: `code-py`
   rules"), load that skill too
4. Run verification commands from both skills (linters, formatters, tests)
5. **Rule-by-rule manual review against golden rules and loaded skills.** Linters only catch
   syntactic issues. You must catch judgment-based violations that linters miss — redundant tests
   covering the same code path, naming that drifts from conventions, philosophy violations (testing
   implementation vs. behavior), structural anti-patterns (classes as grouping, loops in tests), and
   unnecessary complexity.

   **Method — do not skip or abbreviate these sub-steps:**

   - **(a)** Open each skill and enumerate its mandatory rules, pitfall entries, and best-practice
     sections.
   - **(b)** For **each rule**, scan every test function in the file for violations. Do not batch
     rules or skim — check one rule at a time across the full file before moving to the next.
   - **(c)** For merge/redundancy: apply the golden rule merge/keep-separate table pairwise across
     all test functions. Do any two tests assert the same code path with trivially different inputs?
     Could parametrize replace them? Are related edge cases split when they share setup and code
     path? Flag trivial-behavior tests that aren't strictly necessary for coverage — each trivial
     code path should be traversed only once across the suite.
   - **(d)** For naming rules: verify every `test_*` name against the prescribed format. Flag drift
     even when the name is "close enough."
   - **(e)** Respect noted exceptions between skills (e.g., test functions don't need `-> None`
     annotations).
   - **(f)** For **AAA and desiderata** (always, regardless of language): verify every test follows
     Arrange-Act-Assert with clear phase separation. Check test desiderata compliance — especially
     behavioral, structure-insensitive, isolated, deterministic, and specific.
   - **(g)** For **behavior vs. implementation**: check every mock, assertion, and import. Is the
     test asserting internal method calls instead of observable outcomes? Does it import private
     functions (`_helper`, `_parse`, etc.) directly? Would a pure refactor (same behavior, different
     structure) break this test? Flag: direct tests of private functions, mocks of private
     collaborators, exact call-count assertions on internals, and snapshot assertions that
     over-specify.

   **Rationalization guard:** Zero violations in a non-trivial file is a signal to re-check, not a
   sign of perfection. Go back to sub-step (b) and re-examine the top 3 most commonly violated rules
   with fresh eyes before concluding the review.

   | Excuse                                   | Reality                                                            |
   | ---------------------------------------- | ------------------------------------------------------------------ |
   | "I scanned the file and found no issues" | Scanning ≠ rule-by-rule checking. Go back to (b).                  |
   | "The linter would have caught this"      | Linters miss redundancy, naming, philosophy, structure.            |
   | "Tests look reasonable"                  | "Reasonable" skips pairwise comparison. Do (c).                    |
   | "Names are close enough"                 | Close enough ≠ compliant. Check each name in (d).                  |
   | "It's just a trivial helper test"        | If trivial, does it need to exist? Check golden rules.             |
   | "AAA is implied"                         | Implicit ≠ verified. Check phase separation in (f).                |
   | "Each edge case deserves its own test"   | Same code path + different inputs = merge. See table.              |
   | "I need to verify the mock was called"   | Assert the outcome, not the wiring. See (g).                       |
   | "Testing _func directly boosts coverage" | Coverage via private imports is fake. Drive it through public API. |
   | "The mock returns the right value"       | That tests the mock, not the code. See false coverage in (g).      |

6. Fix any issues found

For directories, find all test files recursively. **Only vet test files — never production code.**

## Output Rules

**When called from preflight or another workflow:** Output NOTHING. Accumulate findings internally
for the caller. The parent workflow controls all output.

**When called standalone (direct `/test-vet` invocation):**

- Verification commands: Show name + pass/fail. If skipped, briefly note why.
- Violations: List ONLY violations found with file:line and brief description.
- If everything passes: Just say "No issues found." - nothing else.

**NEVER output:**

- Tables showing all rules/pitfalls with "None found" rows
- Summary of checks that passed
- Progress updates like "Now checking..."
