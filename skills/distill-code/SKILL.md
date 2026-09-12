---
name: distill-code
description: >
  Use when code needs cleanup or simplification after implementation is complete — deep nesting,
  duplicated logic, unclear names, or magic values — and you want to reduce it to its essence
  without changing behavior. Also use when a function is too complex or hard to read, and when a
  cleanup is about to reword a message, swap a guard for a try/except, add a check, or edit a test
  to stay green — those are behavior changes this skill stops. Not for behavior changes or
  architectural rewrites. Not for over-engineering audits — use scan-simplification.
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

## Observable behavior — the bright line

Violating the letter of this section is violating its spirit — there are no technicalities.

Distillation changes how code is written, never what a caller or user can observe. Observable
behavior is every row of this table:

| Observable          | Includes                                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Return values       | Value, type, and the input → output mapping, including the empty and error cases                                            |
| Escaping exceptions | Which exceptions propagate and on which inputs — a guard swapped for `try/except`, or an `except` tuple widened or narrowed |
| Exit codes          | Including the code produced at interpreter shutdown                                                                         |
| User-facing strings | stdout, stderr, log lines, exception messages, `parser.error` text — byte for byte                                          |
| Side effects        | Files, network, environment, and `flush()`/`close()` calls the old code did not make                                        |
| Public signatures   | Names, parameters, defaults, and the precedence between alternative forms                                                   |
| New code paths      | A branch, guard, validation, or call that did not exist is new behavior, even when the old path was an unhandled exception  |

A change to any row is a feature or a bug fix — even one that makes the program better. It gets its
own commit and its own test, from the feature lane. Here it is reported under
`Out of scope —
behavior change:` and the code stays as it was.

**Tests are the oracle.** A distillation never changes an assertion, an expected value, a
parametrize row, or the observable output of a fixture. Restructuring test code — helpers,
constants, merged parametrize decorators — is allowed exactly when every assertion and expected
value survives verbatim. When a cleanup makes a test fail, the cleanup changed behavior: revert the
cleanup, never the test.

## Core Principles

| Principle            | Guidance                                                            |
| -------------------- | ------------------------------------------------------------------- |
| Preserve behavior    | Change HOW, never WHAT — every row of Observable behavior identical |
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

| Mistake                                 | Fix                                                                                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Over-extracting                         | Don't create helpers for one-time operations                                                                                          |
| Renaming without context                | Understand usage before changing names                                                                                                |
| Breaking implicit contracts             | Check callers before changing signatures                                                                                              |
| Removing "redundant" checks             | Never remove error handling, edge-case guards, or defensive code — they often guard cases you don't see                               |
| Rewording a user-facing message         | Message text is output. `could not read` → `could not parse` is a feature commit with its own test, never a cleanup                   |
| Swapping a guard for `try/except`       | `exists()` and `except OSError` accept different inputs — an unreadable path that used to traceback now passes silently with defaults |
| Adding validation while passing through | A new `isinstance` guard is a new code path with no test. Report it under Out of scope; the feature lane adds it with its test        |
| Editing a test to keep a cleanup green  | The red test is the proof the cleanup changed behavior. Revert the cleanup, never the assertion                                       |

## Rationalizations

| Excuse                                                                         | Reality                                                                                               |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| "The message was misleading; the new one is more precise"                      | More precise is a change. Scripts and tests match the old string. Feature lane.                       |
| "grep found no caller matching the old string"                                 | The test did, and the user's shell might. Output text is contract whether or not the repo greps it.   |
| "The test asserts the existing, more precise distinction"                      | The distinction is minutes old — your edit created it. The test was right; the edit changed behavior. |
| "Test-only change, so no behavior note"                                        | A changed expected value is the behavior change made visible.                                         |
| "The old code would traceback; returning a default is friendlier"              | Friendlier is a change. Traceback versus silent default is exactly what a pre-commit hook depends on. |
| "`FileNotFoundError` is a subclass of `OSError`, so catching both is harmless" | The catch is wider than the `exists()` check it replaced. Permission errors now pass silently.        |
| "This flush is the most valuable change in the diff"                           | Then it deserves its own commit and a test that exercises it. Report it; never smuggle it.            |

## Red flags — stop, this is a feature

- You are typing a new string literal that reaches stdout, stderr, a log, or an exception.
- You are widening or narrowing an `except` tuple, or replacing an `if` guard with one.
- You are adding an `isinstance`, `is None`, or validation branch that did not exist.
- You are adding a call — `flush()`, `close()`, logging — the old code did not make.
- A test went red after your change and you are opening the test file.
- Your Why line contains "more precise", "improves", "friendlier", or "was misleading".

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
  Behavior: preserved — <the Observable rows the change touches, and why each is byte-identical>
```

Improvements found but not applied, one line each:

```text
Out of scope — behavior change: file:line - <what would change, and why it is a feature or bug fix>
```
