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

The full anti-pattern catalogue (five patterns with gate functions and fixes) lives in
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

 tdd (inline)   ─first-step→  Skill(test-core)  (hub does the rest)
 tdd (agent loop) → tdd-cycle agent loads Skill(test-core)   (orchestrator loads none)
 vet-test agent ─first-step→  Skill(vet-core) → Skill(test-core)   (loaded inside the agent)
                     └─also→  rules dispatch → Skill(code-{lang})  (code-side review)
 vet-test-merit   ─first-step→  Skill(vet-core) → Skill(test-core)   (loaded inside the agent)
```

`test-core` is the single entry point for all test work. It owns universal principles inline and
dispatches to the matching language skill based on the file extension looked up in
`rules/skill-loading.md`. Loading is one-directional: `test-core` → `test-{lang}`. Language skills
never load `test-core` back.

`tdd` and the `vet-test` and `vet-test-merit` agents are orchestrators of _when_ tests are written
and reviewed. `test-core` defines _what_ a good test looks like. This is why they are peers of the
language skills, not parents of the testing philosophy.

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

- `test-core`, `tdd`, `tdd-cycle`, `vet-test` and `vet-test-merit` agents → **Test skill** column
- `vet-code` and `vet-test` agents, `tdd` (code side) → **Code skill** column
- `preflight` → **Test file patterns** column

Same row, different cells. One source of truth for every language.

### Domain Skill Detection

Each base language skill (`test-py`, `test-ts`, `test-lua`, `test-swift`) has a `## Domain Skill
Detection` section. When the base skill loads, it scans the file's imports and automatically loads
any overlay skills for libraries that need their own testing patterns.

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

The hub. Owns all universal principles inline, each under a named heading:

- Test What the Project Computes: whether a test should exist, which changes get no test, and how
  large a fake may be
- One Test per Distinct Branch: merging cases, parametrize over loops, isolation and determinism
- Test Through the Public API: assert outcomes, never internals; mock only at boundaries
- Test First Only for Logic
- Shape: Arrange-Act-Assert, naming, where new tests go
- Rationalizations, condensed from every past excuse
- Dispatch block: read extension → rules-file table → `Skill(test-{lang})`

Lazy reference: `@references/anti-patterns.md` — loaded when writing or reviewing code that uses
mocks.

### `test-core/references/anti-patterns.md`

Five anti-patterns with gate functions and fixes:

1. Testing mock behavior
2. Test-only methods in production
3. Mocking without understanding
4. Incomplete mocks
5. Stacked assertions over varying inputs

Growth space for future patterns (AP6, AP7, …). Language skills do not duplicate these.

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

- The Iron Law: no logic without a failing test first; a change with no logic is outside it
- Choose the Path: inline test-first in conversation, or the `tdd-cycle` agent loop for plan tasks
- RED-GREEN-REFACTOR orchestration via `tdd-cycle` subagents, with batching and parallel waves, in
  `references/orchestration-flow.md`
- Path-choice rationalizations and red flags in the SKILL.md body; agent-loop rationalizations and
  red flags (orchestrator reading source, dispatching `tdd-cycle` directly) in
  `references/orchestration-flow.md` › Agent Loop Rules

Cross-language testing principles (the "what makes a good test" content) live in `test-core`.

On the inline path, the first step before the first RED-GREEN cycle is `Skill(test-core)`. On the
agent loop the orchestrator loads no testing skill; each `tdd-cycle` agent loads `test-core` itself.

### `tdd/references/orchestration-flow.md`

The RED-GREEN-REFACTOR loop pseudocode, entry-point logic, and phase data contracts, plus the Agent
Loop Rules: dispatch, batching, parallel waves, and the agent loop's rationalizations and red flags.

The tdd-cycle output contract (STATUS values and per-status fields) is owned by
`agents/tdd-cycle.md` § Output Format — the single source of truth. It is deliberately not restated
here; restated copies drift.

### `vet-test` agent

Read-only review agent (`agents/vet-test.md`), dispatched as `subagent_type: vet-test`. Owns the
review _process_, not the review _criteria_. Process:

1. Load `Skill(vet-core)` — the shared reviewer contract (scoring verdicts, scope, Impact, output
   grammar) every reviewer agent fills with its domain slots
2. Load `Skill(test-core)` — cascades to `test-{lang}` and overlays via DSD
3. Look up the target extension in the rules-file Language Dispatch table → `code-{lang}`
4. Load `Skill(code-{lang})`
5. Walk the combined checklist rule-by-rule (not scanning)
6. Return `### Finding N` blocks — Issue, Location, Verdict, Impact, Reasoning

The agent has no `Edit`, `Write`, or `Bash` tools: it reports, and the caller fixes. `/revise-test`
is the interactive entry point that dispatches it and then applies the findings.

`vet-test` does not contain inline testing principles. The checklist is `test-core` principles plus
language-skill rules plus code idioms. It skips `test-core` › Test What the Project Computes, which
`vet-test-merit` owns.

### `vet-test-merit` agent

Read-only review agent (`agents/vet-test-merit.md`), dispatched as `subagent_type: vet-test-merit`.
It asks one question of every test in its bucket: should this test exist? It owns `test-core` › Test
What the Project Computes: tests of anything that principle says gets no test, and fakes heavier
than the logic they reach. It reads the production modules the tests reach, because it names the
project line that decides each assertion.

It makes two passes:

1. **Ledger** — one line per test: the project line that decides it, or `none` plus the case, and a
   decision (`keep`, `delete`, `narrow`, `move first`).
2. **Proportion** — per production module, the test-side lines against the logic lines. A module
   where at least a third of its ledger lines are not `keep` gets one module-level finding.

`/revise-test` and `/harden` dispatch it per bucket next to `vet-test`, and `/preflight` per batch.
Both report a row that repeats a sibling's path; the dispatcher merges the two findings. Repeats
across buckets stay with `vet-test-suite`.

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
