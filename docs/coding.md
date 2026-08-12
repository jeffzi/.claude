# Coding Architecture and Philosophy

This document explains how the production-code skills fit together, what each one owns, and why they
are structured the way they are. The target reader is someone adding a new `code-{lang}` skill,
tracing a rule back to its source, or understanding why a caller loads what it does. For the
parallel testing architecture, see [`docs/testing.md`](testing.md).

## Philosophy

### Quick Code IS Production Code

Code written "just to test something" gets committed. Scripts written "just for CI" run in
production for years. There are no throwaway files.

Write every file as if it ships today: type-annotate every public function signature, add error
handling before it is needed, follow the language's idiomatic style unconditionally, and implement
missing behavior instead of leaving `TODO` comments.

### No Obvious Comments — Explain Why, Not What

Self-documenting code makes the _what_ obvious. Comments are for the _why_: non-obvious decisions,
trade-offs, invariants, references to external context.

```text
# BAD — restates the code
total = 0  # initialize total
for item in items:  # loop through items
    total += item  # add to total

# GOOD — explains a non-obvious constraint
# Use 4095 not 4096: kernel reserves the top page in this range (see POSIX §12.2.3)
LIMIT = 4095
```

If you find yourself writing "this is because...", write the comment. If you find yourself writing
"this does...", delete it.

### Types Are Not Optional

If the language has a type system or annotation mechanism, every public function signature is
annotated. No exceptions for "too simple", "internal", or "will stabilize later." Simple functions
still call other code; internal functions are the most-changed; stability comes from types.

The leaf skill owns the language-specific syntax: PEP 484 signatures in Python, `unknown` over `any`
in TypeScript, LuaLS annotations in Lua, `Sendable` in Swift, none required in shell.

### Errors Must Surface

An error swallowed is a bug waiting to manifest somewhere unrelated. Errors must propagate to a
point where the caller can act on them.

Never:

- Catch an exception and log it without re-raising or returning an error value.
- Start an async task and discard its result without a handler.
- Return `null`/`nil`/`false` from a function that can legitimately return those values on the
  success path.

The leaf skill owns the language mechanism:

- Python: EAFP with specific exception types, `ExceptionGroup` for task failures
- TypeScript: `return await` in try/catch, every Promise `.catch()`ed or `await`ed
- Lua: `nil, err` return tuples for expected failures
- Swift: typed throws, `withTaskCancellationHandler`, no fire-and-forget `Task { }`
- Shell: `set -euo pipefail`, `trap` for cleanup

### Verification Is Mandatory Before Completion

**A task is NOT complete until lint, type-check, and tests all pass.**

"Should work" is not verification. "Looks correct" is not verification. Running the commands and
seeing green output is verification. The leaf skill owns the exact commands.

### Universal Rationalizations

| Excuse                                      | Reality                                                      |
| ------------------------------------------- | ------------------------------------------------------------ |
| "Just prototyping"                          | Prototypes become production. Write it right the first time. |
| "Would add types in production code"        | Quick code IS production code.                               |
| "This is too simple to need types"          | Simple code changes. Types prevent silent breakage.          |
| "I'll clean it up later"                    | Later never comes. The code ships as written.                |
| "It works on my machine"                    | That is not the production environment.                      |
| "I'll add error handling once it's working" | Broken error handling is harder to add than to build in.     |
| "The test suite would have caught this"     | Not if it wasn't run.                                        |

### Red Flags — Stop and Fix

If any of these are true, stop before proceeding:

- A function signature has no type annotations in a typed language.
- A comment describes what the next line of code does.
- An async operation's result is discarded without a handler.
- A `TODO` references behavior that must exist for the feature to work.
- The verification commands have not been run since the last edit.
- A `catch`/`except`/`recover` block is empty or only logs.
- Code contains `@ts-ignore`, `# type: ignore`, `#pragma: no cover`, or equivalent suppression
  without an explanatory comment.

> Behavior-focused testing, Arrange-Act-Assert, mocking anti-patterns — those live in
> [`docs/testing.md`](testing.md). Nothing in this document repeats them.

## Architecture

### Overview

```text
 rules/skill-loading.md   ← canonical extension → skill map (in every session via CLAUDE.md)
          │
     code-core            ← hub: 5 mandatory rules; dispatches to language skills
     ├── code-py          ← leaf: PEP 484, ruff, uv, EAFP
     │   ├── code-marimo  ← overlay: DSD on marimo notebook structure
     │   ├── code-shiny   ← overlay: DSD on `from shiny import`
     │   └── polars       ← overlay: DSD on `import polars`
     ├── code-ts          ← leaf: strict tsconfig, no `as` casts, no floating promises
     │   └── code-tstl    ← overlay: DSD on `tstl` in tsconfig.json
     │       └── code-tstl-plugin  ← two-layer: DSD from code-tstl on Plugin impl
     ├── code-lua         ← leaf: LuaLS annotations, nil-err tuples
     ├── code-swift       ← leaf: strict concurrency, Sendable, typed throws
     └── code-shell       ← leaf: bash/sh only; auto-activates via paths glob (see §Design decisions)

 vet-code agent ─first-step→  Skill(code-core)  (loaded inside the agent; hub does the rest)
 tdd (GREEN)    ─first-step→  Skill(code-core)
```

`code-core` is the single entry point for all production-code work. It owns universal rules inline
and dispatches to the matching language skill based on the file extension looked up in
`rules/skill-loading.md`. Loading is one-directional: `code-core` → `code-{lang}`. Language skills
never load `code-core` back.

The `vet-code` agent and `tdd` (GREEN phase) are consumers of _when_ the rules are applied.
`code-core` defines _what_ production-grade code looks like. This is why they are peers of the
language skills, not parents of the philosophy.

### Language dispatch

The extension-to-skill map lives in `rules/skill-loading.md` under **Language Dispatch for test-\*
and code-\***.

| Ext(s)                        | Test skill | Code skill | Test file patterns         |
| ----------------------------- | ---------- | ---------- | -------------------------- |
| `.py`, `.pyi`                 | test-py    | code-py    | `test_*.py`, `*_test.py`   |
| `.ts`, `.tsx`, `.mts`, `.cts` | test-ts    | code-ts    | `*.test.ts`, `*.spec.ts`   |
| `.lua`                        | test-lua   | code-lua   | `*_test.lua`, `*_spec.lua` |
| `.swift`                      | test-swift | code-swift | `*Tests.swift`             |

Each column serves a different caller:

- `code-core`, `tdd` (code side) → **Code skill** column
- `test-core`, `tdd` (test side) → **Test skill** column
- `vet-test` agent, `preflight` → **Test file patterns** column

Same row, different cells. One source of truth for every language.

> **`code-shell` is deliberately absent from this table.** Shell files appear as `.sh`, `.bash`, or
> with no extension at all. Rather than maintaining a growing list of extensions — and still missing
> extensionless shebangs — `code-shell` auto-activates via its `paths: "**/*.sh, **/*.bash"` glob in
> SKILL frontmatter. This is an explicit exception, not a pattern to copy; see Design decisions.

### Domain Skill Detection

Each base language skill (`code-py`, `code-ts`, `code-lua`, `code-swift`) has a
`## Domain Skill Detection` section. When the base skill loads, it scans the file's imports and
automatically loads any overlay skills for libraries that need their own code patterns.

```text
code-py loads
  → DSD scans imports
  → detects "import polars"
  → loads polars

code-ts loads
  → DSD scans tsconfig.json / imports
  → detects "tstl" in tsconfig
  → loads code-tstl
      → DSD scans for Plugin implementation
      → loads code-tstl-plugin
```

`code-tstl` is the only overlay that itself owns a Domain Skill Detection section. It extends
`code-ts` (not `code-core` directly) and cascades one level deeper into `code-tstl-plugin`. This is
the single two-layer case in the architecture; see Design decisions for why it exists.

Import-level detection is more precise than config-level: if polars is installed but the current
file does not import it, there is no reason to load `polars` into context.

Every base language skill carries a `## Domain Skill Detection` section — a prose note when no
overlays exist yet, populated with a table when they do. Overlays themselves do not have DSD
sections (except `code-tstl`).

## What each skill owns

### `code-core`

The hub. Owns all universal rules inline:

- Core principle: quick code is production code
- No obvious comments — explain why, not what
- Types are not optional (every public signature)
- Errors must surface
- Verification is mandatory before completion
- Project conventions bind like skill rules
- Universal rationalizations table
- Red flags list

No `references/` subdirectory — `code-core` is self-contained. Unlike `test-core`'s
`references/anti-patterns.md`, there is no separate catalogue of code anti-patterns yet; all
universal guidance fits inline.

### `code-{lang}` (pure leaves)

Language-specific syntax, idioms, verification commands, pitfalls, and language-specific
rationalizations. One entry per leaf:

- **`code-py`**: Modern 3.10+ syntax, dataclass defaults, EAFP exception patterns, `pyproject.toml`
  version check, imports-at-top rule, PEP 758
- **`code-ts`**: No `as` casts (+ acceptable uses), no `any` leaks from `JSON.parse`, no floating
  promises, `unknown` + schema validation at boundaries, house-tsconfig pointer to `setup-ts`
- **`code-lua`**: LuaLS annotations, `nil, err` return tuples, naming conventions
- **`code-swift`**: Strict concurrency, `Sendable`, typed throws, no fire-and-forget `Task { }`,
  `withTaskCancellationHandler`
- **`code-shell`**: bash/sh only (not zsh/fish/PowerShell), `set -euo pipefail`, shellcheck/shfmt,
  `trap` for cleanup, proper quoting

What leaves do **not** contain: the rationale for types-mandatory, the rationale for
errors-must-surface, the universal rationalization table. The principle lives in `code-core`; the
language mechanism lives in the leaf.

Header convention on each leaf:

> "This skill extends `Skill(code-core)`. `code-core` is the primary entry point; this skill is
> loaded by `code-core` based on the rules-file dispatch table."

No `Skill(code-core)` call. The leaf does not pull its parent.

### Overlays

Overlays attach to a base leaf via Domain Skill Detection. They do not appear in the dispatch table;
they load at import-detection time by the base leaf.

- **`code-marimo`**: Reactive notebook DAG cells, SQL-first analysis, forbidden patterns (global
  keyword, on_change callbacks, mo.state). Attached to `code-py`.
- **`code-shiny`**: Reactive Express/Core mode, reactive.value lifecycle, extended_task for
  long-running ops, session cleanup. Attached to `code-py`.
- **`polars`**: DataFrame idioms, expression chains, lazy vs. eager evaluation. Attached to
  `code-py`.
- **`code-tstl`**: TSTL Lua-5.1 codegen patterns, `$range()` for numeric loops, LuaMap/LuaSet.
  Attached to `code-ts`. Extends `code-ts` (not `code-core`) — the only two-layer case.
- **`code-tstl-plugin`**: TSTL visitor transforms, printer overrides. Attached to `code-tstl`.

### `vet-code` agent

Read-only review agent (`agents/vet-code.md`), dispatched as `subagent_type: vet-code`. Owns the
review _process_, not the review _criteria_. Process:

1. Load `Skill(code-core)` — hub dispatches to `code-{lang}` and overlays via DSD
2. Walk the combined checklist rule-by-rule (not scanning) for each mandatory rule, pitfall entry,
   and Instead-of/Use table from the loaded skills
3. Return `### Finding N` blocks — Issue, Location, Score, Reasoning

The agent has no `Edit`, `Write`, or `Bash` tools: it reports, and the caller fixes. `/revise-code`
is the interactive entry point that dispatches it and then applies the findings.

`vet-code` does not contain inline code principles. The checklist is `code-core` principles plus
language-skill rules and idioms.

### `tdd` GREEN phase

`tdd` loads `Skill(test-core)` at entry. The GREEN sub-phase — writing production code to make a
failing test pass — should additionally load `Skill(code-core)` before writing any production code.
Full TDD orchestration is covered in [`docs/testing.md`](testing.md).

## Design decisions

### Hub-to-leaf, not leaf-to-hub

The hub gives one entry point. Loading is one-directional, eliminating circular chains and the risk
of a language skill loading `code-core` back. The parallel test-skill case is documented in
[`docs/testing.md`](testing.md).

### Rules file, not a skill, for dispatch

The dispatch table lives in `rules/skill-loading.md` — already in every session's context via
`CLAUDE.md` — so it costs nothing extra and has no caller who might forget to load it. The parallel
test-skill case is documented in [`docs/testing.md`](testing.md).

### Import-level overlay detection

Base-skill DSD detects at import level, not config level: if a library is installed but the current
file does not import it, there is no reason to load its overlay. The parallel test-skill case is
documented in [`docs/testing.md`](testing.md).

### Universal rules in `code-core`, not in `tdd`

All five mandatory rules apply whenever production code is written or reviewed — not only during a
GREEN cycle. Keeping them in `code-core` ensures every production-code workflow applies them, and
`tdd` picks them up transitively through `Skill(code-core)` in the GREEN phase.

### `code-shell` as a paths-only special case

Shell files arrive with `.sh`, `.bash`, no extension, or any extension (`.env`, `.profile`). A
dispatch-table row would need to enumerate a non-exhaustive list and still miss extensionless
shebangs. The `paths:` glob in the SKILL frontmatter (`**/*.sh, **/*.bash`) handles the common cases
through the harness's built-in auto-activation, without requiring shebang detection.

This is an intentional exception. New languages must follow the dispatch-table route — do not copy
this pattern. The trade-off is that `code-shell` does not appear in `rules/skill-loading.md`, so
orchestrators that resolve languages from the table (like the `vet-test` agent, since there is no
`test-shell`) cannot discover it automatically.

### The `code-tstl` two-layer overlay

`code-tstl` is the only overlay in the architecture that itself carries a Domain Skill Detection
section and has its own child overlay (`code-tstl-plugin`). This exists because TSTL is strictly a
subset of TypeScript — all `code-ts` rules (strict types, no `as`, no floating promises) still apply
when writing TSTL. A direct `code-core` → `code-tstl` link would lose all code-ts discipline.

Extending `code-ts` preserves that discipline and adds TSTL-specific codegen costs on top. The chain
is finite (three layers: `code-ts` → `code-tstl` → `code-tstl-plugin`) and one-directional. Do not
generalize — this pattern applies only when a transpiled-target sub-ecosystem has enough surface
area to need its own overlays.

## Extending the architecture

### Adding a new language

1. Create `skills/code-{lang}/SKILL.md` as a pure leaf — add the "extends Skill(code-core)" header,
   an empty `## Domain Skill Detection` stub, and language-specific syntax, pitfalls, and
   verification commands. Do not restate the five mandatory rules.
2. Add a row to the Language Dispatch table in `rules/skill-loading.md`.
3. Also create `skills/test-{lang}/SKILL.md` — see [`docs/testing.md`](testing.md).

No changes to `code-core` unless the new language introduces a universal rule not yet in the hub.
See [`docs/languages.md`](languages.md) for the complete step-by-step workflow.

### Adding a new overlay

1. Create `skills/code-{lib}/SKILL.md` with `user-invocable: false`.
2. Add a trigger row to the base language skill's `## Domain Skill Detection` table.

The hub and dispatch table require no changes. See [`docs/languages.md`](languages.md) for templates
and examples.

### Adding a new universal rule

Add it to `code-core` inline (under Mandatory Rules, Rationalizations, or Red Flags — whichever
fits). All callers — the `vet-code` agent, `tdd` GREEN, direct writing — pick it up through the hub.
No leaf changes needed unless a language has a specialized mechanism for the new rule (add an
example row to the leaf's relevant section).
