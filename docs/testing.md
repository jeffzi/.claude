# Testing Architecture and Philosophy

This document explains how the testing skills fit together, what each one owns, and why they are
structured the way they are. The target reader is someone adding a new test skill, tracing a
philosophy decision back to its source, or trying to understand why a particular caller loads what
it does.

## Philosophy

### Test behavior, not implementation

Assert what the code **does** — outputs, return values, side effects, state changes — not how it
does it internally. A refactor that preserves observable behavior should never break a test.

| Fragile (implementation-coupled)               | Resilient (behavior-focused)                         |
| ---------------------------------------------- | ---------------------------------------------------- |
| Assert an internal method was called           | Assert the observable output or state changed        |
| Mock private helpers or internal collaborators | Mock only at system boundaries (I/O, network, clock) |
| Verify exact call count or order on mocks      | Verify the end result                                |
| Assert the shape of an internal data struct    | Assert the public API contract                       |
| Snapshot an entire object to check one field   | Assert only the relevant field(s)                    |
| Import and test a private function directly    | Drive coverage through the public API                |

If you can change the implementation without changing the behavior and your test breaks, the test is
coupled to implementation.

### Arrange-Act-Assert

Every test has three phases in order: set up preconditions (Arrange), execute the behavior under
test — one action (Act), then verify the outcome (Assert). No logic between phases. No assertions in
Arrange. "And" in the test name is a signal to split it.

### Minimum tests, maximum coverage

| Merge when                         | Keep separate when    |
| ---------------------------------- | --------------------- |
| Same code path, different inputs   | Different code paths  |
| Related edge cases (nil, empty, 0) | Complex setup differs |
| Same behavior across APIs          | Tests need isolation  |

Do not test trivial behavior unless strictly necessary to traverse a code path. Even then, traverse
each trivial code path purposefully once across the entire test suite.

### Parametrize over loops

When the same code path runs with varying inputs, use the language's parametrization mechanism — not
a loop inside a single test function. Loops stop at the first failure; parametrization reports each
case independently and names them.

| Language   | Mechanism                                          |
| ---------- | -------------------------------------------------- |
| Python     | `@pytest.mark.parametrize("a,b,expected", [...])`  |
| TypeScript | `test.each([...])` / `it.each([...])` in Vitest    |
| Lua        | Loop over table driving a separate `it()` per case |
| Swift      | `@Test(arguments: [...])` in Swift Testing         |

### Mocks isolate; they do not test

A test that mocks a collaborator and asserts the mock's own return value exercises zero real logic.
If removing the production code would not fail the test, the test covers nothing.

Mock at system boundaries — I/O, network, clock. Test internal logic through the public API.

The full anti-pattern catalogue (six patterns with gate functions and fixes) lives in
`test-core/references/anti-patterns.md`. Load it before writing or reviewing any code that uses
mocks.

### Never test private functions directly

If a private function is not reachable through the public API, either it is dead code or the public
API is too narrow. Fix the design; do not test the internals. Coverage via private imports is false
coverage.

### Isolation and determinism

Every test must be **isolated** (same result regardless of run order) and **deterministic** (same
result if nothing changes).

## Architecture

### Overview

```text
 rules/skill-loading.md   ← canonical extension → skill map (in every session via CLAUDE.md)
          │
     test-core            ← hub: universal principles; dispatches to language skills
     ├── test-py          ← leaf: pytest, fixtures, hypothesis
     │   └── test-polars  ← overlay: loaded by test-py DSD when polars is imported
     ├── test-ts          ← leaf: Vitest API, fake timers, type-safe factories
     ├── test-lua         ← leaf: busted, spies, parametrized tests
     └── test-swift       ← leaf: Swift Testing, XCTest, concurrency

 tdd            ─first-step→  Skill(test-core)  (hub does the rest)
 vet-test agent ─first-step→  Skill(test-core)   (loaded inside the agent)
                     └─also→  rules dispatch → Skill(code-{lang})  (code-side review)
```

`test-core` is the single entry point for all test work. It owns universal principles inline and
dispatches to the matching language skill based on the file extension looked up in
`rules/skill-loading.md`. Loading is one-directional: `test-core` → `test-{lang}`. Language skills
never load `test-core` back.

`tdd` and the `vet-test` agent are orchestrators of _when_ tests are written and reviewed.
`test-core` defines _what_ a good test looks like. This is why they are peers of the language
skills, not parents of the testing philosophy.

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

- `test-core`, `tdd`, `tdd-cycle` → **Test skill** column
- `vet-code` agent, `tdd` (code side) → **Code skill** column
- `preflight`, `vet-test` agent → **Test file patterns** column

Same row, different cells. One source of truth for every language.

### Domain Skill Detection

Each base language skill (`test-py`, `test-ts`, `test-lua`, `test-swift`) has a
`## Domain Skill Detection` section. When the base skill loads, it scans the file's imports and
automatically loads any overlay skills for libraries that need their own testing patterns.

```text
test-py loads
  → DSD scans imports
  → detects "import polars"
  → loads test-polars
```

Import-level detection is more precise than config-level (checking `pyproject.toml` deps): if polars
is installed but the current test file does not import it, there is no reason to load `test-polars`
into context.

Every base language skill carries a `## Domain Skill Detection` section — a prose note when no
overlays exist yet, populated with a table when they do. Overlays themselves do not have DSD
sections.

## What each skill owns

### `test-core`

The hub. Owns all universal principles inline:

- Core principle: test behavior, not implementation
- Arrange-Act-Assert (one canonical definition)
- Isolation and determinism
- Fragile vs. Resilient table
- Merge rules — Minimum Tests, Maximum Coverage
- Never test private functions directly
- False coverage detection
- Parametrize over loops (language-agnostic formulation)
- Universal rationalizations and red flags
- Dispatch block: read extension → rules-file table → `Skill(test-{lang})`

Lazy reference: `@references/anti-patterns.md` — loaded when writing or reviewing code that uses
mocks.

### `test-core/references/anti-patterns.md`

Six mock anti-patterns with gate functions and fixes:

1. Testing mock behavior
2. Test-only methods in production
3. Mocking without understanding
4. Incomplete mocks
5. Integration tests as afterthought
6. Stacked assertions over varying inputs

Growth space for future patterns (AP7, AP8, …). Language skills do not duplicate these.

### `test-{lang}` (pure leaves)

Language-specific syntax and pitfalls only. Examples of what lives here:

- `test-py`: `autospec=True`, naming form, no-classes-for-grouping, `pytest.param` ids,
  hypothesis/moto/seeding guidance
- `test-ts`: `toStrictEqual` vs `toEqual`, async timer APIs, fake timer cleanup, `test.each` vs
  `test.for`, type-safe factory pattern
- `test-lua`: `assert.are_same` for tables, `before_each` for isolation, parametrized test
  generation
- `test-swift`: `@Test(arguments:)`, `confirmation()`, `TestScoping`, Sendable mock patterns,
  `withMainSerialExecutor`, clock injection

What leaves do **not** contain: the rationale for AAA, the rationale for parametrize, merge rules,
rationalizations. The principle lives in `test-core`; the language syntax lives in the leaf.

Header convention on each leaf:

> "This skill extends `Skill(test-core)`. `test-core` is the primary entry point; this skill is
> loaded by `test-core` automatically based on the rules-file dispatch table."

No `Skill(test-core)` call. The leaf does not pull its parent.

### `tdd`

TDD orchestrator. Owns:

- The Iron Law: no production code without a failing test first
- RED-GREEN-REFACTOR orchestration via `tdd-cycle` subagents
- Plans → agents → verification flow
- Batching rules (cohesive vs. unrelated behaviors)
- TDD-specific rationalizations ("I'll test after", "plan has inline impl")
- TDD-specific red flags (code before test, orchestrator reading source, dispatching `tdd-cycle`
  directly)

First step before the first RED-GREEN cycle: `Skill(test-core)`.

### `tdd/references/philosophy.md`

TDD-orchestration-only content: the Iron Law, TDD-specific rationalizations, TDD-specific red flags.
Cross-language testing principles (the "what makes a good test" content) live in `test-core`.

### `tdd/references/orchestration-flow.md`

The RED-GREEN-REFACTOR loop pseudocode, entry-point logic, and phase data contracts. Pure
orchestration, no philosophy.

The tdd-cycle output contract (STATUS values and per-status fields) is owned by
`agents/tdd-cycle.md` § Output Format — the single source of truth. It is deliberately not restated
here; restated copies drift.

### `vet-test` agent

Read-only review agent (`agents/vet-test.md`), dispatched as `subagent_type: vet-test`. Owns the
review _process_, not the review _criteria_. Process:

1. Load `Skill(test-core)` — cascades to `test-{lang}` and overlays via DSD
2. Look up the target extension in the rules-file Language Dispatch table → `code-{lang}`
3. Load `Skill(code-{lang})`
4. Walk the combined checklist rule-by-rule (not scanning)
5. Return `### Finding N` blocks — Issue, Location, Score, Reasoning

The agent has no `Edit`, `Write`, or `Bash` tools: it reports, and the caller fixes. `/revise-test`
is the interactive entry point that dispatches it and then applies the findings.

`vet-test` does not contain inline testing principles. The checklist is `test-core` principles plus
language-skill rules plus code idioms.

## Design decisions

### Hub-to-leaf, not leaf-to-hub

The hub gives one entry point: `test-core` answers "which language?" by looking up the extension.
Loading is one-directional — no circular chains, no risk of a language skill loading `test-core`
which then re-dispatches back to the same language skill.

### Rules file, not a skill, for dispatch

Two jobs, two homes:

- **Extension map** → `rules/skill-loading.md`: already loaded in every session via `CLAUDE.md`, so
  the map costs nothing extra. There is no caller who might forget to load it; no version that could
  drift. One file, always in scope, always authoritative.
- **Overlay detection** → base-skill DSD: operates at import level, which is more precise than
  config-level detection. A library in `pyproject.toml` does not mean the current test file uses it.

### Import-level overlay detection

Base-skill DSD detects at import level (does this test file actually `import polars`?), not at
config level (is `polars` listed in `pyproject.toml`?). Import-level is strictly more precise: if
polars is installed but the current test does not use DataFrames, there is no reason to load
`test-polars` into context.

### Anti-patterns in `test-core`, not in `tdd`

All six mock anti-patterns apply whenever tests are written or reviewed — not only during a
RED-GREEN cycle. They live in `test-core` so every test workflow applies them; `tdd` picks them up
transitively through `Skill(test-core)`.

## Extending the architecture

See [`docs/languages.md`](languages.md) for the complete workflow for adding a new language or
overlay. New universal testing anti-patterns go in `test-core/references/anti-patterns.md` (see
§"What each skill owns" above).
