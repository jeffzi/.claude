---
name: code-core
description: >
  Use when writing or reviewing production code in any language. Covers quick-code-is-production,
  comment policy, mandatory types, error surfacing, verification gates, and universal
  rationalizations. Not for test code — use `Skill(test-core)`.
user-invocable: false
---

# Production Code — Cross-Language Principles

After loading this skill, read the file's extension, look it up in the Language Dispatch table in
`rules/skill-loading.md`, and load the matching `Skill(code-{lang})` leaf. The leaf owns all
language-specific idioms, pitfalls, and verification commands.

## Mandatory Rules

### 1. Quick Code IS Production Code

Code written "just to test something" gets committed. Scripts written "just for CI" run in
production for years. There are no throwaway files. Write every file as if it ships today, and do
not leave `TODO` comments that track missing behavior — implement it or open a ticket.

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

### 4. Errors Must Surface

An error swallowed is a bug waiting to manifest somewhere unrelated. **Errors must propagate to a
point where the caller can act on them.**

Never:

- Catch an exception and log it without re-raising or returning an error value.
- Start an async task and discard its result without a handler.
- Return `null`/`nil`/`false` from a function that can legitimately return those values on the
  success path — callers cannot distinguish error from valid result.

### 5. Verification Is Mandatory Before Completion

**A task is NOT complete until lint, type-check, and tests all pass.**

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

**Violating the letter of these rules is violating the spirit of the rules.**

| Excuse                                      | Reality                                                      |
| ------------------------------------------- | ------------------------------------------------------------ |
| "Just prototyping"                          | Prototypes become production. Write it right the first time. |
| "Would add types in production code"        | Quick code IS production code.                               |
| "This is too simple to need types"          | Simple code changes. Types prevent silent breakage.          |
| "I'll clean it up later"                    | Later never comes. The code ships as written.                |
| "It works on my machine"                    | That is not the production environment.                      |
| "I'll add error handling once it's working" | Broken error handling is harder to add than to build in.     |
| "The test suite would have caught this"     | Not if it wasn't run.                                        |

## Red Flags — Stop and Fix

- A function signature has no type annotations in a typed language.
- A comment describes what the next line of code does.
- A comment tells the reader what the code used to be, or which alternative was rejected.
- An async operation's result is discarded without a handler.
- A `TODO` references behavior that must exist for the feature to work.
- The verification commands have not been run since the last edit.
- A `catch`/`except`/`recover` block is empty or only logs.
- Code contains `@ts-ignore`, `# type: ignore`, `#pragma: no cover`, or equivalent suppression
  without an explanatory comment.
