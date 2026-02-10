---
name: test-vet
description: Vet test files for rule and pitfall violations
argument-hint: "[test file or directory]"
---

# Test Vet

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
5. **Read the code and manually review it against the FULL content of both skills.** Linters only
   catch a subset of issues. You must inspect the code yourself against every section of each skill
   — mandatory rules, pitfalls, best practices, patterns, idioms, and any other guidance the skills
   provide. Walk through the file looking for each violation or missed opportunity. Respect noted
   exceptions between skills (e.g., test functions don't need `-> None` annotations).
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
