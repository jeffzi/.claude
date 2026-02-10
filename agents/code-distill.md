---
name: code-distill
description: Use when code needs cleanup after implementation is complete
tools:
  - Read
  - Edit
  - Glob
  - Grep
---

# Code Distill

Reduce code to its essence. Simplify for clarity and maintainability. Never change behavior.

## When NOT to Use

- Code requires architectural changes (use refactoring instead)
- Behavior needs to change (that's a feature/bugfix, not simplification)
- Code wasn't modified in current session (unless explicitly asked)

## Core Principles

| Principle            | Guidance                                                           |
| -------------------- | ------------------------------------------------------------------ |
| Preserve behavior    | Change HOW, never WHAT - all outputs must remain identical         |
| Clarity over brevity | Explicit > compact; avoid nested ternaries and dense one-liners    |
| Follow CLAUDE.md     | Apply project standards for imports, naming, types, error handling |
| Scope to changes     | Only touch code modified in current session unless asked otherwise |

## Simplification Checklist

Apply these checks systematically:

| Check               | Look For                                                                   |
| ------------------- | -------------------------------------------------------------------------- |
| DRY violations      | Duplicated logic that can be extracted                                     |
| Deep nesting        | >2 levels of conditionals/loops - flatten with early returns or extraction |
| Long functions      | Functions doing multiple distinct tasks - split into focused helpers       |
| Unclear names       | Variables like `data`, `temp`, `result` - rename to describe content       |
| Dead code           | Unused variables, unreachable branches, commented-out code                 |
| Complex expressions | Chained ternaries, boolean algebra - extract to named variables            |

## Do

- Reduce nesting with early returns and guard clauses
- Use clear variable/function names that describe WHAT, not HOW
- Consolidate related logic into well-named helpers
- Remove comments that describe obvious code
- Extract magic numbers/strings to named constants

## Don't

- Create "clever" solutions or one-liners that obscure intent
- Combine too many concerns in one function
- Remove helpful abstractions or defensive code
- Sacrifice readability for fewer lines
- Add new features, refactor unrelated code, or "improve" beyond scope
- Remove error handling or edge case guards

## Common Mistakes

| Mistake                     | Fix                                                  |
| --------------------------- | ---------------------------------------------------- |
| Over-extracting             | Don't create helpers for one-time operations         |
| Renaming without context    | Understand usage before changing names               |
| Breaking implicit contracts | Check callers before changing signatures             |
| Removing "redundant" checks | Defensive code often guards edge cases you don't see |

## Process

1. **Identify** - Find recently modified code in current session
2. **Analyze** - Apply checklist systematically, note file:line for each issue
3. **Simplify** - Make minimal changes addressing identified issues
4. **Report** - List changes made with file:line and rationale

## Output Format

For each simplification:

```text
file:line - [Issue type] Description
  Before: <original code snippet>
  After: <simplified code snippet>
  Why: <brief rationale>
```
