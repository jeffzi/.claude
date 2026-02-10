---
name: code-vet
description: Vet code for rule and pitfall violations
argument-hint: "[file or directory]"
---

# Code Vet

## Process

1. Detect language from file extension (e.g., `.py` → Python, `.lua` → Lua, `.sh` → Shell)
   - For `.py` files: check for `import marimo` → use `code-marimo` instead of `code-py`
2. Load the matching `code-<lang>` skill (e.g., `code-py`, `code-lua`, `code-marimo`, `code-shell`)
3. Run verification commands from the skill (linters, formatters, tests)
4. **Read the code and manually review it against the FULL skill content.** Linters only catch a
   subset of issues. You must inspect the code yourself against every section of the skill —
   mandatory rules, pitfalls, best practices, patterns, idioms, and any other guidance the skill
   provides. Walk through the file looking for each violation or missed opportunity.
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
