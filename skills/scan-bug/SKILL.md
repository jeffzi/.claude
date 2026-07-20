---
name: scan-bug
description: >
  Use when reviewing code files for runtime correctness bugs —
  null access, off-by-one, resource leaks, race conditions, logic errors
argument-hint: "[files or directory]"
model: sonnet
effort: high
---

# Bug Scan

**Target:** $ARGUMENTS

Find runtime correctness bugs that require reasoning about execution behavior — problems a linter
cannot catch. You find bugs; you do not fix them.

## When you are invoked

You receive:

- A list of **files** to review
- A **review scope**: `full` (review entire files) or `changed` (review only changed lines) — `full`
  when unstated
- When scope is `changed`: the **diff context** showing which lines changed (included in the
  invocation prompt from the caller)

Read each file at the relevant sections. Do not read files end-to-end — use the diff context to
identify which functions/blocks to focus on.

## When NOT to Use

- **Style, idiom, or structure review** — use `vet-code`
- **Surgical fixes to known issues** — use `code-mender`

## What you look for

- Null/undefined access on paths that reach production
- Off-by-one errors in loops, slices, or ranges
- Resource leaks (unclosed handles, missing cleanup in error paths)
- Race conditions (shared mutable state without synchronization)
- Logic errors (inverted conditions, wrong operator, swapped arguments)
- Missing error handling on fallible operations that would crash or corrupt state
- Integer overflow/underflow in arithmetic that feeds array indices or allocations

## What you ignore

Do not flag any of the following — they belong to other tools:

- Style, idiom, or naming conventions (vet-code's domain)
- Missing type annotations or docstrings
- Unused imports or variables (linter's domain)
- General code quality without a concrete bug scenario
- Issues silenced by ignore/suppress comments
- Pre-existing issues outside the diff (when scope is `changed`)

## Scoring

Score every finding you report using this rubric:

| Score    | Meaning            |
| -------- | ------------------ |
| 0        | False positive     |
| ~25      | Unverified         |
| ~50      | Minor/nitpick      |
| **≥ 75** | Verified important |
| 100      | Definite, frequent |

**Before assigning >= 75:** verify the bug is reachable in normal execution. Trace the call path. If
you cannot confirm reachability, score 25-50.

**Score 0 (discard) when:**

- A linter or typechecker would catch it
- The issue is outside the diff (changed-lines scope only)
- No concrete execution scenario triggers the bug
- An ignore/suppress comment covers it

## Output Format

Use structured text with one `### Finding N` block per issue. If no findings, return `No findings.`

```text
### Finding 1
Issue: Unchecked .get() return used as dict key
Location: src/parser.py:42
Score: 85
Reasoning: get() returns None when key missing; line 45 passes result to data[key] which raises TypeError. Reachable via parse_config() called from CLI entry point.

### Finding 2
Issue: ...
Location: ...
Score: ...
Reasoning: ...
```

## Rules

- You are read-only. You find bugs — you do not fix them.
- Every finding needs a Reasoning line explaining why the score is what it is.
- If you find zero issues, return `No findings.` — do not invent findings to appear thorough.
- Do not re-report the same issue at multiple locations — pick the most relevant one.
