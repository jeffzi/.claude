---
name: distill-code
description: >
  Use when code needs cleanup or simplification after implementation is complete — deep nesting,
  duplicated logic, unclear names, or magic values — and you want to reduce it to its essence
  without changing behavior. Also use when a function is too complex or hard to read. Not for
  behavior changes or architectural rewrites. Not for over-engineering audits — use
  scan-simplification.
argument-hint: "[file-or-directory...]"
---

# Distill Code

Reduce code to its essence — improve clarity and maintainability without ever changing behavior.

## When NOT to Use

- Whole-abstraction deletion or speculative layers — use `Skill(scan-simplification)`
- Idiom, typing, or structural rule violations — use `Skill(revise-code)`
- Behavior needs to change (that's a feature/bugfix, not simplification)
- No specific files or code were named

Your unit is the expression, block, and name — not the architecture.

## Core Principles

| Principle            | Guidance                                                            |
| -------------------- | ------------------------------------------------------------------- |
| Preserve behavior    | Change HOW, never WHAT - all outputs must remain identical          |
| Clarity over brevity | Explicit > compact; avoid nested ternaries and dense one-liners     |
| Scope to changes     | Only touch files specified in the invocation unless asked otherwise |

## Simplification Checklist

Apply these checks systematically:

| Check               | Look For                                                                                 |
| ------------------- | ---------------------------------------------------------------------------------------- |
| DRY violations      | Duplicated logic that can be consolidated into well-named helpers                        |
| Deep nesting        | >2 levels of conditionals/loops - flatten with early returns and guard clauses           |
| Long functions      | Functions doing multiple distinct tasks - split into focused helpers                     |
| Unclear names       | Variables like `data`, `temp`, `result` - rename to describe content                     |
| Dead code           | Unused variables, unreachable branches, commented-out code                               |
| Magic values        | Unnamed numeric literals, string constants, repeated values - extract to named constants |
| Complex expressions | Chained ternaries, boolean algebra - extract to named variables                          |

## Common Mistakes

| Mistake                     | Fix                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------- |
| Over-extracting             | Don't create helpers for one-time operations                                                            |
| Renaming without context    | Understand usage before changing names                                                                  |
| Breaking implicit contracts | Check callers before changing signatures                                                                |
| Removing "redundant" checks | Never remove error handling, edge-case guards, or defensive code — they often guard cases you don't see |

## Process

1. **Load rules** - `Skill(code-core)` once per distinct file extension among the targets; it
   dispatches the matching language leaf
2. **Analyze** - Apply the checklist systematically, note file:line for each issue
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
