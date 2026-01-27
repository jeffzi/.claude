---
name: vet
description: Vet code for best practices and idiomatic patterns
argument-hint: "[file or directory]"
---

# Vet Code

## Process

1. Detect language from file extension (e.g., `.py` → Python, `.lua` → Lua)
   - For `.py` files: check for `import marimo` → use `code-marimo` instead of `code-py`
2. Load the matching `code-<lang>` skill (e.g., `code-py`, `code-lua`, `code-marimo`)
3. Run verification commands from the skill
4. Check EVERY pitfall in the skill's Pitfalls table
5. Fix any issues found

For directories, detect from file extensions present.

## Output Rules

**CRITICAL: Minimal output only. Do NOT show passing checks or "clean" tables.**

- Verification commands: Show name + pass/fail. If skipped, briefly note why.
- Pitfall violations: List ONLY violations found. Do NOT create tables showing passing checks.
- If everything passes: Just say "No issues found." - nothing else.
