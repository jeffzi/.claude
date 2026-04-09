---
name: vet-code
description: Use when reviewing code files for idiom, type, and structural violations the linter won't catch
argument-hint: "[file or directory]"
model: sonnet
effort: medium
---

# Code Vet

**Target:** $ARGUMENTS

## Overview

Linters catch syntactic issues. Code vet catches judgment-based violations — non-idiomatic patterns,
wrong abstractions, missing type hints, and structural issues that automated tools miss.

## Process

The command is a **pure orchestrator**. The loaded code-X skill owns the rules, pitfalls, and
patterns — this workflow just routes the file through the skill's own checklist. Do not substitute
generic review methodology for the skill's content.

1. **Resolve the code skill(s).** If the caller already passed a `CODE_SKILL` argument, use it and
   skip this step. Otherwise, load `Skill(resolve-lang-skills)`. Derive lang from the file's
   extension. `CODE_SKILL = code-{lang}` plus any active project overlays (check project config once
   per project root; reuse for subsequent files). Unknown extension → `CODE_SKILL` is `none` — skip
   skill-based review and note it.

2. **Load each resolved code skill via `Skill()`** in order (most-specific first). Their mandatory
   rules, pitfall entries, and Instead-of/Use tables become the checklist for steps 4–6.

3. **Run the skill's verification commands** (linters, formatters, tests). Record pass/fail per
   command.

4. **Rule-by-rule manual review.** Enumerate the skill's mandatory rules, pitfall entries, and
   Instead-of/Use tables as an explicit checklist. For **each rule**, scan every function/class in
   the file for violations before moving to the next rule. Do not batch rules. Flag deviations even
   when the code "works."

   **Rationalization guard:** Zero violations in a non-trivial file is a signal to re-check, not a
   sign of perfection. Re-examine the rules the skill marks as mandatory or most-commonly-violated
   with fresh eyes before concluding.

   | Excuse                                   | Reality                                                       |
   | ---------------------------------------- | ------------------------------------------------------------- |
   | "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk the skill's checklist again.    |
   | "The linter would have caught this"      | Linters miss idiom, abstraction, and structural issues.       |
   | "Code works correctly"                   | Working ≠ idiomatic. Check the skill's Instead-of/Use tables. |
   | "The skill's rules are obvious"          | Obvious ≠ applied. Cite the rule section for each check.      |

5. **Fix each issue**, citing which skill rule was violated. Re-run the verification commands from
   step 3 to confirm no regressions.

**Directory targets:** recurse into subdirectories, skipping `node_modules/`, `__pycache__/`,
`.git/`, `dist/`, `build/`, `.venv/`. Resolve overlays once per project root, derive `CODE_SKILL`
per file from its extension, and repeat steps 1–6 per file. Report findings per file, grouped by
language.

## Output Rules

**When called from preflight or another workflow:** Output NOTHING. Accumulate findings internally
for the caller. The parent workflow controls all output.

**When called standalone (direct `/vet-code` invocation):**

- Verification commands: Show name + pass/fail. If skipped, briefly note why.
- Violations: List ONLY violations found with file:line and brief description.
- If everything passes: Just say "No issues found." - nothing else.

**NEVER output:**

- Tables showing all rules/pitfalls with "None found" rows
- Summary of checks that passed
- Progress updates like "Now checking..."
