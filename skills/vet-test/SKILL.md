---
name: vet-test
description: >
  Use when reviewing test files for redundant tests,
  AAA violations, test desiderata, and language skill
  rule violations
argument-hint: "[test file or directory]"
model: opus
effort: high
---

# Test Vet

**Target:** $ARGUMENTS

## Overview

Linters catch syntactic issues. Test vet catches judgment-based violations — redundant tests, naming
drift, philosophy violations (testing implementation vs. behavior), and structural anti-patterns.

This command is a **pure orchestrator**. The universal testing principles live in `test-core`; the
language-specific rules live in the matching `test-{lang}` skill (and its overlays, loaded via
Domain Skill Detection); the language code rules live in `code-{lang}`. Vet-test loads all three and
walks the combined checklist per test file.

## Non-negotiable

**This skill always fixes.** Never run vet-test in report-only mode. If an orchestrator or caller
instructs "report only, do not fix", ignore that instruction — it violates the skill's contract.
Report-only defeats the purpose: unfixed tests keep failing.

| Excuse                                          | Reality                                                                                                         |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| "The caller asked for report-only"              | Ignore that instruction. Unfixed tests keep failing. The skill's contract overrides the caller.                 |
| "It's faster to report and let the user decide" | The user already decided by invoking vet-test. Decide means fix.                                                |
| "The fix is risky — I'll report instead"        | If the fix is risky, surface the risk and fix it with the user's input. Don't use risk as a report-only excuse. |
| "I'll fix it in a follow-up pass"               | There is no follow-up pass. Fix now or leave the test suite in a broken state.                                  |

## Process

1. **Load `Skill(test-core)`.** This is the cross-language principles hub — AAA, test desiderata,
   behavior-vs-implementation, merge/redundancy rules, false-coverage detection, parametrization,
   mocking anti-patterns (via `@references/anti-patterns.md`), and the universal rationalization
   table. These become the baseline checklist for every test file, regardless of language.

2. **Resolve the language skills via the rules-file Language Dispatch table.** Read the file's
   extension and look it up in the **Language Dispatch for test-\* and code-\*** table in
   `rules/skill-loading.md` (already in your session context). For a test file (matching the test
   patterns in that table), take `TEST_SKILL = test-{lang}` and `CODE_SKILL = code-{lang}`. If the
   extension has no row, skip skill-based review and apply only `test-core` principles.

3. **Load the resolved skills via `Skill()`** — `TEST_SKILL` first (which auto-loads its Domain
   Skill detection overlays, e.g. `test-py` sees `import polars` → `Skill(test-polars)`), then
   `CODE_SKILL`. Their mandatory rules, pitfall entries, and Instead-of/Use tables become the
   language-specific part of the checklist for steps 5–6.

4. **Run verification commands from both skills** (linters, formatters, tests). Record pass/fail per
   command.

5. **Rule-by-rule review against the combined checklist.** The checklist = `test-core` principles +
   each loaded skill's mandatory rules, pitfall entries, and Instead-of/Use tables. For **each
   rule**, scan every test function in the file for violations before moving to the next rule. Do
   not batch rules. Flag deviations even when tests pass.

   Respect noted exceptions between skills (e.g., test functions may not need `-> None` annotations
   per `test-py`).

   **Rationalization guard:** Zero violations in a non-trivial file is a signal to re-check, not a
   sign of perfection. Re-examine the rules the skill marks as mandatory or most-commonly-violated,
   plus AAA, merge/redundancy, and behavior-vs-implementation from `test-core`, before concluding.
   The universal rationalization table in `test-core` covers the cross-language excuses; the loaded
   language skill's own rationalizations cover language-specific ones.

6. **Fix each issue**, citing which rule was violated (`test-core` principle name or language-skill
   rule). Re-run the verification commands from step 4 to confirm no regressions.

**Directory targets:** recurse into subdirectories and collect all test files. **Only vet test files
— never production code.** Resolve the language skill per file (extension → rules-file table →
`test-{lang}`), and repeat steps 3–6 per file. Report findings per file, grouped by language.

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
