---
name: code-vet
description: Use when reviewing code files for language skill rule and pitfall violations
argument-hint: "[file or directory]"
---

# Code Vet

## Overview

Linters catch syntactic issues. Code vet catches judgment-based violations — non-idiomatic patterns,
wrong abstractions, missing type hints, and structural issues that automated tools miss.

## Process

1. Detect language from file extension (e.g., `.py` → Python, `.lua` → Lua, `.sh` → Shell)
   - For `.py` files: check for `import marimo` → use `code-marimo` instead of `code-py`
2. Load the matching `code-<lang>` skill (e.g., `code-py`, `code-lua`, `code-marimo`, `code-shell`)
3. Run verification commands from the skill (linters, formatters, tests)
4. **Rule-by-rule manual review against the skill.** Linters only catch syntactic issues. You must
   catch judgment-based violations that linters miss — non-idiomatic patterns, wrong abstraction
   choices, error handling anti-patterns, missing or incorrect type hints, and structural issues
   (e.g., manual classes where dataclasses suffice, LBYL where EAFP applies).

   **Method — do not skip or abbreviate these sub-steps:**

   - **(a)** Open the skill and enumerate its mandatory rules, pitfall entries, and best-practice
     sections.
   - **(b)** For **each rule**, scan every function/class in the file for violations. Do not batch
     rules or skim — check one rule at a time across the full file before moving to the next.
   - **(c)** For idiom/pattern rules: actively compare the code against the skill's "Instead of →
     Use" tables and common-pattern references. Flag deviations even when the existing code "works."
   - **(d)** For type hint rules: verify every function signature has complete annotations. Check
     for stale `Optional`/`Union`/`List` imports that should use modern syntax.

   **Rationalization guard:** Zero violations in a non-trivial file is a signal to re-check, not a
   sign of perfection. Go back to sub-step (b) and re-examine the top 3 most commonly violated rules
   with fresh eyes before concluding the review.

   | Excuse                                   | Reality                                                 |
   | ---------------------------------------- | ------------------------------------------------------- |
   | "I scanned the file and found no issues" | Scanning ≠ rule-by-rule checking. Go back to (b).       |
   | "The linter would have caught this"      | Linters miss idiom, abstraction, and structural issues. |
   | "Code works correctly"                   | Working ≠ idiomatic. Check against (c) tables.          |
   | "Type hints are mostly there"            | Mostly ≠ complete. Verify every signature in (d).       |

5. Fix any issues found

For directories, detect from file extensions present.

## Output Rules

**When called from preflight or another workflow:** Output NOTHING. Accumulate findings internally
for the caller. The parent workflow controls all output.

**When called standalone (direct `/code-vet` invocation):**

- Verification commands: Show name + pass/fail. If skipped, briefly note why.
- Violations: List ONLY violations found with file:line and brief description.
- If everything passes: Just say "No issues found." - nothing else.

**NEVER output:**

- Tables showing all rules/pitfalls with "None found" rows
- Summary of checks that passed
- Progress updates like "Now checking..."
