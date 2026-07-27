---
name: code-core
description: >
  Use when writing or reviewing production code in any language. Covers quick-code-is-production,
  comment policy, mandatory types, error surfacing, verification gates, and universal
  rationalizations. Not for test code — use `Skill(test-core)`.
user-invocable: false
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

**A _why_ binds the current code.** It tells the next editor what changing this would break. History
does not: a previous implementation, a dropped dependency, an alternative considered and rejected,
the backstory of a decision — those belong in the changelog, the PR, or the docs, which are built to
carry them. The reader of a source file should not have to learn what the code used to be.

Same subject, opposite verdicts — the difference is whether it constrains the next edit:

```text
# GOOD — binds the next edit
# Do not reintroduce cli-width: stream.columns covers every Node version we support.

# BAD — narrates the past
# We originally reached for cli-width, but dropped the dependency in the 0.4 cycle.
```

When a constraint is buried in past tense, keep the constraint and drop the narration — don't delete
both.

```text
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
```

**Line-anchored suppressions bind to their target line.** `*-ignore-next-line`,
`eslint-disable-next-line`, `# noqa`, `@ts-expect-error` and kin suppress the line immediately after
(or on) them. When editing near one — including adding the explanatory comment these suppressions
should carry — keep the suppression directly above its target; the explanation goes above the
suppression or on its own line, never between the suppression and the code it covers. Splitting that
pair silently un-suppresses the target and can turn a passing check red.

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

### 6. Project Conventions Bind Like These Rules

The project's CLAUDE.md (and files it imports, such as AGENTS.md) may state its own conventions —
output routing, naming, module layout, annotation requirements. Where present, they join this
skill's rules with equal force: writing code, follow them; reviewing code, cite them exactly like a
skill rule (`CLAUDE.md: "<quoted convention>"`). A stated project convention is never a "style
preference" — the project already made that decision. Only imperative rules about code content
qualify: command references, build instructions, and architecture notes are documentation, not
conventions, and bind nothing.

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
- A comment tells the reader what the code used to be, or which alternative was rejected.
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
| `vet-code` agent                      | Loads `Skill(code-core)` in its own context; hub dispatches to the leaf      |
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
  .sh, .bash       →  Skill(code-shell)
```

If the extension is not listed, check whether a `code-{lang}` skill exists under `skills/` with a
matching `paths:` glob. If none exists, note "no matching skill" rather than guessing.
