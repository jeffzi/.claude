---
name: vet-test
description: >
  Use when reviewing test files for redundant tests,
  AAA violations, test desiderata, and language skill
  rule violations
argument-hint: "[test file or directory]"
model: sonnet
effort: medium
---

# Test Vet

**Target:** $ARGUMENTS

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

The command is a **pure orchestrator**. The loaded test-X skill (plus any `code-<lang>` skill it
cross-references) owns the language-specific rules, pitfalls, and patterns. The Golden Rules above
are the cross-language baseline the command enforces **alongside** the skill's checklist — not
instead of it.

1. **Resolve the test and code skill(s).** If the caller already passed `TEST_SKILL` and
   `CODE_SKILL` arguments, use them and skip this step. Otherwise, load
   `Skill(resolve-lang-skills)`. Derive lang from the file's extension and check test file detection
   patterns. `TEST_SKILL = test-{lang}` if the file matches test patterns, else `none`.
   `CODE_SKILL = code-{lang}` plus any active project overlays (check project config once per
   project root; reuse for subsequent files). If `TEST_SKILL` is `none`, skip skill-based test
   review and apply only the Golden Rules. If `CODE_SKILL` is `none`, proceed without
   cross-referenced code rules.

2. **Load all resolved skills via `Skill()`** — each `TEST_SKILL` entry first (most-specific first),
   then each `CODE_SKILL` entry. Their mandatory rules, pitfall entries, and Instead-of/Use tables
   become the checklist for steps 4–6, combined with the Golden Rules above.

3. **Run verification commands from both skills** (linters, formatters, tests). Record pass/fail per
   command.

4. **Rule-by-rule review against the combined checklist.** The checklist = Golden Rules above + the
   loaded skill's mandatory rules, pitfall entries, and Instead-of/Use tables. For **each rule**,
   scan every test function in the file for violations before moving to the next rule. Do not batch
   rules. Flag deviations even when tests pass.

   Respect noted exceptions between skills (e.g., test functions may not need `-> None` annotations
   per `test-py`).

   **Rationalization guard:** Zero violations in a non-trivial file is a signal to re-check, not a
   sign of perfection. Re-examine the rules the skill marks as mandatory or most-commonly-violated,
   plus AAA, merge/redundancy, and behavior-vs-implementation from the Golden Rules, before
   concluding.

   | Excuse                                   | Reality                                                         |
   | ---------------------------------------- | --------------------------------------------------------------- |
   | "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk the combined checklist again.     |
   | "The linter would have caught this"      | Linters miss redundancy, naming, philosophy, structure.         |
   | "Tests look reasonable"                  | "Reasonable" skips pairwise comparison. Apply the merge table.  |
   | "AAA is implied"                         | Implicit ≠ verified. Check phase separation per test.           |
   | "Each edge case deserves its own test"   | Same code path + different inputs = merge. See Golden Rules.    |
   | "I need to verify the mock was called"   | Assert the outcome, not the wiring. See behavior-vs-impl table. |
   | "Testing _func directly boosts coverage" | Coverage via private imports is fake. Drive through public API. |
   | "The mock returns the right value"       | That tests the mock, not the code. See false coverage note.     |
   | "The skill's rules are obvious"          | Obvious ≠ applied. Cite the rule section for each check.        |

5. **Fix each issue**, citing which rule was violated (Golden Rule section or skill rule). Re-run
   the verification commands from step 3 to confirm no regressions.

**Directory targets:** recurse into subdirectories and collect all test files. **Only vet test files
— never production code.** Resolve overlays once per project root, derive `TEST_SKILL` and
`CODE_SKILL` per file from extension and test patterns, and repeat steps 1–6 per file. Report
findings per file, grouped by language.

## Output Rules

**When called from preflight or another workflow:** Output NOTHING. Accumulate findings internally
for the caller. The parent workflow controls all output.

**When called standalone (direct `/vet-test` invocation):**

- Verification commands: Show name + pass/fail. If skipped, briefly note why.
- Violations: List ONLY violations found with file:line and brief description.
- If everything passes: Just say "No issues found." - nothing else.

**NEVER output:**

- Tables showing all rules/pitfalls with "None found" rows
- Summary of checks that passed
- Progress updates like "Now checking..."
