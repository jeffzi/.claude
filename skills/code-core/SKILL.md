---
name: code-core
description: >
  Use when writing or reviewing production code in any language. Covers quick-code-is-production,
  comment policy, mandatory types, error surfacing, verification gates, and universal
  rationalizations. Not for test code — use `Skill(test-core)`.
user-invocable: false
model: sonnet
effort: medium
---

# Production Code — Cross-Language Principles

**Core principle:** Production-grade from keystroke one. There is no such thing as temporary code
that stays temporary.

After loading this skill, read the file's extension, look it up in the Language Dispatch table in
`rules/skill-loading.md`, and load the matching `Skill(code-{lang})` leaf. The leaf owns all
language-specific idioms, pitfalls, and verification commands.

## Mandatory Rules

### 1. Quick Code IS Production Code

Code written "just to test something" gets committed. Scripts written "just for CI" run in
production for years. There are no throwaway files.

Write every file as if it ships today:

- Type-annotate every public function signature.
- Add error handling before it's needed.
- Follow the language's idiomatic style unconditionally.
- Do not leave `TODO` comments that track missing behavior — implement it or open a ticket.

The leaf skill owns the language-specific syntax for each of these. The rule is universal.

### 2. No Obvious Comments — Explain Why, Not What

Self-documenting code makes the _what_ obvious. Comments are for the _why_: non-obvious decisions,
trade-offs, invariants, references to external context (ticket number, paper, spec section). Never
reference line numbers — they drift on the next edit; name the invariant, function, or symbol.

````text
# BAD — restates the code
total = 0  # initialize total
for item in items:  # loop through items
    total += item  # add to total

# BAD — line number drifts on next edit
# see line 42 for the retry logic

# GOOD — explains a non-obvious constraint
# Use 4095 not 4096: kernel reserves the top page in this range (see POSIX §12.2.3)
LIMIT = 4095

# GOOD — names the function, not the line
# see validate_token() for the retry logic
```text

Delete comments before refactoring a function, then add them back only where the new code can't
speak for itself. If you find yourself writing "this is because...", write the comment. If you find
yourself writing "this does...", delete it.

### 3. Types Are Not Optional

If the language has a type system or annotation mechanism, every public function signature is
annotated. No exceptions for:

- "This function is too simple to need types" — simple functions still call other code.
- "It's internal" — internal functions are the most-changed and most-broken.
- "I'll add types when the code stabilizes" — types are what make the code stable.

The leaf skill owns the language-specific syntax: PEP 484 signatures in Python, `unknown` over `any`
in TypeScript, LuaLS annotations in Lua, Sendable in Swift, none required in shell.

### 4. Errors Must Surface

An error swallowed is a bug waiting to manifest somewhere unrelated. **Errors must propagate to a
point where the caller can act on them.**

Never:

- Catch an exception and log it without re-raising or returning an error value.
- Start an async task and discard its result without a handler.
- Return `null`/`nil`/`false` from a function that can legitimately return those values on the
  success path — callers cannot distinguish error from valid result.

The leaf skill owns the language mechanism:

- Python: EAFP with specific exception types, `ExceptionGroup` for task failures.
- TypeScript: `return await` in try/catch, every Promise `.catch()`ed or `await`ed.
- Lua: `nil, err` return tuples for expected failures.
- Swift: typed throws, `withTaskCancellationHandler`, no fire-and-forget `Task { }`.
- Shell: `set -euo pipefail`, `trap` for cleanup.

### 5. Verification Is Mandatory Before Completion

**A task is NOT complete until lint, type-check, and tests all pass.**

"Should work" is not verification. "Looks correct" is not verification. Running the commands and
seeing green output is verification. The leaf skill owns the exact commands.

Common traps:

- Linting and type-checking are separate commands — run both.
- Tests exist in a subdirectory you didn't touch — run the whole suite, not just the touched file.
- Pre-commit hooks run a subset of checks — run the full check independently.

## Universal Rationalizations

These excuses apply in every language. Recognize them as signals that a shortcut is about to be
taken.

| Excuse                                      | Reality                                                      |
| ------------------------------------------- | ------------------------------------------------------------ |
| "Just prototyping"                          | Prototypes become production. Write it right the first time. |
| "Would add types in production code"        | Quick code IS production code.                               |
| "This is too simple to need types"          | Simple code changes. Types prevent silent breakage.          |
| "I'll clean it up later"                    | Later never comes. The code ships as written.                |
| "It works on my machine"                    | That is not the production environment.                      |
| "I'll add error handling once it's working" | Broken error handling is harder to add than to build in.     |
| "The test suite would have caught this"     | Not if it wasn't run.                                        |

The leaf skill has language-specific rationalizations for idiomatic traps that don't apply
cross-language (e.g., "as casts are fine in TypeScript", "LuaLS annotations slow me down").

## Red Flags — Stop and Fix

If any of these are true, stop before proceeding:

- A function signature has no type annotations in a typed language.
- A comment describes what the next line of code does.
- An async operation's result is discarded without a handler.
- A `TODO` references behavior that must exist for the feature to work.
- The verification commands have not been run since the last edit.
- A `catch`/`except`/`recover` block is empty or only logs.
- Code contains `@ts-ignore`, `# type: ignore`, `#pragma: no cover`, or equivalent suppression
  without an explanatory comment.

## Downstream Consumers

| Caller                                | How code-core is loaded                                                      |
| ------------------------------------- | ---------------------------------------------------------------------------- |
| `rules/skill-loading.md` action table | Loaded automatically when writing code — hub dispatches to leaf              |
| `vet-code`                            | Step 1: load `Skill(code-core)`; hub dispatches to the matching leaf         |
| `tdd` (code/GREEN side)               | Should load `Skill(code-core)` before writing production code in GREEN phase |

**Overlays** (e.g., `code-shiny`, `code-marimo`, `code-tstl`, `polars`) are loaded by the base
_leaf_ skill's own Domain Skill Detection — not by this hub. The hub has no knowledge of overlays.

## Language Dispatch

Look up the file's extension in `rules/skill-loading.md` under **Language Dispatch for test-\* and
code-\*** — the `Code skill` column. Load that skill.

```text
rules/skill-loading.md → Code skill column
  .py, .pyi        →  Skill(code-py)
  .ts, .tsx, …     →  Skill(code-ts)
  .lua             →  Skill(code-lua)
  .swift           →  Skill(code-swift)
  .sh, .bash       →  Skill(code-shell)   ← note: not in rules/skill-loading.md; auto-activates via paths
```text

If the extension is not listed, check whether a `code-{lang}` skill exists under `skills/` with a
matching `paths:` glob. If none exists, note "no matching skill" rather than guessing.
````
