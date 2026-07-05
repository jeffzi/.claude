---
name: vet-code
description: Use when reviewing code files for idiom, type, and structural violations the linter won't catch
argument-hint: "[file or directory]"
model: opus
effort: high
---

# Code Vet

**Target:** $ARGUMENTS

## Overview

Linters catch syntactic issues. Code vet catches judgment-based violations — non-idiomatic patterns,
wrong abstractions, missing type hints, and structural issues that automated tools miss.

## Process

The command is a **pure orchestrator**. The universal production-code principles live in
`code-core`; the language-specific rules live in the matching `code-{lang}` leaf (and its overlays,
loaded via Domain Skill Detection). Vet-code loads both and walks the combined checklist per file.

1. **Load `Skill(code-core)`.** This is the cross-language principles hub —
   quick-code-is-production, comment policy, mandatory types, error surfacing, verification gates,
   and universal rationalizations. These become the baseline checklist for every production code
   file, regardless of language.

2. **Resolve the language skill via the rules-file Language Dispatch table.** Read the file's
   extension and look it up in the **Language Dispatch for test-\* and code-\*** table in
   `rules/skill-loading.md` (already in your session context). Take `CODE_SKILL = code-{lang}`. If
   the extension has no row, `CODE_SKILL` is `none` — skip skill-based review and apply only
   `code-core` principles.

3. **Load the resolved code skill via `Skill()`**. The base skill's Domain Skill Detection section
   (if present) auto-loads any library overlays based on the file's imports (e.g. `code-py` sees
   `import polars` → `Skill(polars)`). The loaded skills' mandatory rules, pitfall entries, and
   Instead-of/Use tables extend the checklist for steps 5–6.

4. **Run the skill's verification commands** (linters, formatters, tests). Record pass/fail per
   command.

5. **Rule-by-rule review against the combined checklist.** The checklist = `code-core` principles +
   the loaded language skill's mandatory rules, pitfall entries, and Instead-of/Use tables. For
   **each rule**, scan every function/class in the file for violations before moving to the next
   rule. Do not batch rules. Flag deviations even when the code "works."

   **Rationalization guard:** Zero violations in a non-trivial file is a signal to re-check, not a
   sign of perfection. Re-examine the rules the skill marks as mandatory or most-commonly-violated,
   plus the quick-code, types, and error-surfacing rules from `code-core`, before concluding. The
   universal rationalization table in `code-core` covers cross-language excuses; the language
   skill's own rationalizations cover language-specific ones.

   | Excuse                                   | Reality                                                       |
   | ---------------------------------------- | ------------------------------------------------------------- |
   | "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk the skill's checklist again.    |
   | "The linter would have caught this"      | Linters miss idiom, abstraction, and structural issues.       |
   | "Code works correctly"                   | Working ≠ idiomatic. Check the skill's Instead-of/Use tables. |
   | "The skill's rules are obvious"          | Obvious ≠ applied. Cite the rule section for each check.      |

6. **Fix each issue**, citing which rule was violated (`code-core` principle name or language-skill
   rule). Re-run the verification commands from step 4 to confirm no regressions.

**Directory targets:** recurse into subdirectories, skipping `node_modules/`, `__pycache__/`,
`.git/`, `dist/`, `build/`, `.venv/`. Resolve overlays once per project root, derive `CODE_SKILL`
per file from its extension, and repeat steps 2–6 per file. Report findings per file, grouped by
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
