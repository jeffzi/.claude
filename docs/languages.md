# Adding languages and overlays

This document is the single guide for extending the `code-*` and `test-*` skill architectures.
Adding real support for a language almost always requires touching both sides — production-code
rules and testing conventions — which is why they live here together rather than split across
separate docs.

**What this doc covers:** [Adding a new language](#adding-a-new-language),
[adding a library overlay for an existing language](#adding-an-overlay-for-an-existing-language),
and [special cases](#special-cases).

**What this doc does not cover:** Philosophy — read [`docs/coding.md`](coding.md) for
production-code principles and [`docs/testing.md`](testing.md) for testing principles. Skill-writing
mechanics — read `write-skill`.

## Architecture in one diagram

```text
 rules/skill-loading.md   ← single extension → skill map; in every session via CLAUDE.md
          │
     code-core            ← hub: 5 mandatory production-code rules
     ├── code-py          ← leaf
     │   ├── code-marimo  ← overlay (loaded by code-py DSD)
     │   ├── code-shiny   ← overlay
     │   └── polars       ← overlay
     ├── code-ts          ← leaf
     │   └── code-tstl    ← overlay
     │       └── code-tstl-plugin  ← two-layer overlay (loaded by code-tstl DSD)
     ├── code-lua         ← leaf
     ├── code-swift       ← leaf
     └── code-shell       ← leaf (paths-only; absent from dispatch table — exception)

     test-core            ← hub: universal testing principles
     ├── test-py          ← leaf
     │   └── test-polars  ← overlay (loaded by test-py DSD)
     ├── test-ts          ← leaf
     ├── test-lua         ← leaf
     └── test-swift       ← leaf
```

Hubs own universal principles. Leaves own language-specific syntax and pitfalls. Overlays load
automatically when the base leaf detects a matching import pattern (Domain Skill Detection). Loading
is one-directional — leaves never load their hub back, and overlays never load their base leaf back.

The `rules/skill-loading.md` Language Dispatch table is the **single source of truth** that feeds
every orchestrator: the `vet-code` and `vet-test` agents, `tdd`, `tdd-cycle`, `preflight`, `fix`,
`build`. A row in that table is all that is needed; no orchestrator requires individual changes.

## Decision tree

| You want to support…                                       | You are adding   | Go to                                                            |
| ---------------------------------------------------------- | ---------------- | ---------------------------------------------------------------- |
| A new file extension (Rust, Go, Zig)                       | A language       | [Adding a new language](#adding-a-new-language)                  |
| A library within an existing language (FastAPI, SvelteKit) | An overlay       | [Adding an overlay](#adding-an-overlay-for-an-existing-language) |
| A rule that applies to every language                      | A universal rule | [Adding a new universal rule](#adding-a-new-universal-rule)      |
| A shell-like case with no test infrastructure              | An exception     | [Special cases: code-shell](#code-shell--no-dispatch-row)        |

## Adding a new language

Five steps. Do them in order — step 1 is the prerequisite for the verification in step 5.

### Step 1 — Add a dispatch row

Open `rules/skill-loading.md` and add a row to the **Language Dispatch for test-\* and code-\***
table. Example for Rust:

```markdown
| `.rs` | test-rust | code-rust | `*_test.rs` |
```

Include: extension(s), test skill name, code skill name, test file glob patterns. This single row
feeds every orchestrator. No other configuration is needed.

### Step 2 — Create `skills/code-{lang}/SKILL.md`

Copy [`docs/templates/code-lang.md`](templates/code-lang.md) and fill in the placeholders.

**DO:**

- Fill in language-specific idioms, pitfalls, and verification commands.
- Include a `## Domain Skill Detection` section even if empty (a prose stub is fine).
- Set `paths:` to the glob that matches this language's file extensions.

**DO NOT:**

- Restate `code-core` principles (quick-code-is-production, comment policy, types-mandatory,
  error-surfacing, verification-mandatory). They are already loaded via the hub.
- Call `Skill(code-core)` from inside the leaf — loading is one-directional.
- Add a `user-invocable: true` field — all leaf skills are `false`.

See `skills/code-py/SKILL.md` for a working canonical example.

### Step 3 — Create `skills/test-{lang}/SKILL.md`

Copy [`docs/templates/test-lang.md`](templates/test-lang.md) and fill in the placeholders.

See `skills/test-py/SKILL.md` for a working canonical example.

### Step 4 — Update README tables

Add one row to the **Code** skills table and one row to the **Testing** skills table in `README.md`.
Follow the existing `Skill | Description` format. Example rows:

```markdown
| Skill                                    | Description                                   |
| ---------------------------------------- | --------------------------------------------- |
| [`code-rust`](skills/code-rust/SKILL.md) | Rust: ownership rules, error handling, Clippy |
| [`test-rust`](skills/test-rust/SKILL.md) | Rust tests with the built-in test harness     |
```

### Step 5 — Verify dispatch

Run the reviewers against a small sample file with the new extension:

```bash
/revise-code path/to/sample.{ext}
/revise-test path/to/sample_test.{ext}
```

Each command dispatches its reviewer agent, which resolves the language from the dispatch table.
Confirm both resolve to the new `code-{lang}` and `test-{lang}` skills — the agents report the
skills they loaded on the first line of their findings. If either reports "no matching skill", the
dispatch row or the skill filename does not match.

> **No orchestrator changes are needed.** The `vet-code` and `vet-test` agents, `tdd`, `tdd-cycle`,
> `preflight`, `fix`, and `build` all resolve languages through the rules-file dispatch table.

## Adding an overlay for an existing language

An overlay targets a specific library within a language (e.g., `code-shiny` for Shiny within Python,
`test-polars` for Polars DataFrame testing in Python).

### Step 1 — Decide the surface

Does this library change _how you write the code_ (→ `code-{lib}`), _how you test it_ (→
`test-{lib}`), or both? Most libraries only need one side. When in doubt, start with one and add the
other if gaps appear in practice.

### Step 2 — Create the overlay skill

```markdown
---
name: code-{lib} # or test-{lib}
description: >
  Use when working with {Lib} in {Lang}. Also use when encountering {Lib}-specific errors
  like "...". Not for standard {Lang} — use code-{lang} alone.
user-invocable: false
model: sonnet
effort: high
---

# {Lib} for {Lang}

**This skill extends `Skill(code-{lang})`.** `code-{lang}` is the base for general {Lang} standards;
this skill adds {Lib}-specific patterns on top.
```

Set `user-invocable: false`. Do **not** add a `paths:` glob — overlays are loaded by DSD, not by
file extension. See `skills/code-shiny/SKILL.md` (code overlay) and `skills/test-polars/SKILL.md`
(test overlay) for canonical examples.

### Step 3 — Add a DSD row to the base language skill

Open the base language skill (e.g., `skills/code-py/SKILL.md`) and add a row to its
`## Domain Skill Detection` table:

```markdown
| Import pattern                           | Skill to load  |
| ---------------------------------------- | -------------- |
| `import fastapi` / `from fastapi import` | `code-fastapi` |
```

**Import-level triggers only.** DSD detects `import X` / `from X import` patterns, not
`pyproject.toml` or `package.json` dependencies. If the current file does not import the library,
there is no reason to load the overlay into context.

**No other changes required** — the rules file, hub skills, and orchestrators do not need updating.

## Adding a new universal rule

A rule that applies to every language belongs in the hub, not in any leaf.

- **Production-code rule** → add to `code-core/SKILL.md` (under Mandatory Rules, Rationalizations,
  or Red Flags — whichever fits). All callers — the `vet-code` agent, `tdd` GREEN, direct writing —
  pick it up through the hub. If a language has a specialized mechanism for the new rule, add an
  example row to that leaf's relevant section.
- **Testing anti-pattern** → add to `test-core/references/anti-patterns.md`. All callers — `tdd`,
  the `vet-test` agent, direct test writing — pick it up through the hub.

See [`docs/coding.md`](coding.md) §"Design decisions" and [`docs/testing.md`](testing.md) §"Design
decisions" for criteria on when a rule qualifies as universal vs. language-specific.

## Special cases

### `code-shell` — no dispatch row

`code-shell` is intentionally absent from the `rules/skill-loading.md` dispatch table. Shell files
arrive with `.sh`, `.bash`, no extension, or various environment file names. Rather than maintaining
a non-exhaustive list that still misses extensionless shebangs, `code-shell` auto-activates via its
`paths: "**/*.sh, **/*.bash"` glob in SKILL frontmatter.

**This is a historical exception — do not copy this pattern.** New languages should follow the
5-step sequence above using the dispatch table. The trade-off with `code-shell` is that table-driven
orchestrators cannot resolve a leaf skill for it — they fall back to hub-only review (`code-core`
alone), with `code-shell` activating via its `paths:` glob only when the file is actually read
(there is no `test-shell` and shell files have no standardized test infrastructure in these
projects).

### `code-tstl` — two-layer overlay

```markdown
code-core → code-ts → code-tstl → code-tstl-plugin
```

`code-tstl` is the only overlay that itself carries a `## Domain Skill Detection` section and has
its own child overlay. It extends `code-ts` (not `code-core`) because TSTL is a strict subset of
TypeScript — all `code-ts` rules (no `as` casts, no `any`, no floating promises) still apply when
targeting Lua 5.1. A direct `code-core → code-tstl` link would lose all TypeScript discipline.

Use this two-layer pattern only when a transpiled-target sub-ecosystem has enough surface area to
warrant its own overlays — an entire sub-ecosystem, not just a few import patterns. The chain must
remain finite and one-directional.

See `skills/code-tstl/SKILL.md` for the canonical example.

## Verification checklist

After adding a language, run through this list before declaring it supported:

- [ ] Dispatch row exists in `rules/skill-loading.md` Language Dispatch table
- [ ] `skills/code-{lang}/SKILL.md` exists with `**This skill extends \`Skill(code-core)\`.**`
      header
- [ ] `skills/test-{lang}/SKILL.md` exists with `**This skill extends \`Skill(test-core)\`.**`
      header
- [ ] Both leaves have a `## Domain Skill Detection` section (empty stub is acceptable)
- [ ] Both leaves have a `## Verification` section with concrete commands
- [ ] `README.md` Code Skills table updated
- [ ] `README.md` Testing Skills table updated
- [ ] `/revise-code` and `/revise-test` run successfully against a sample file of the new extension

## Common mistakes

- **Restating hub principles in the leaf.** If you are writing about types-mandatory,
  errors-must-surface, quick-code-is-production, AAA, or parametrize-over-loops in a leaf, stop.
  Those live in the hub and are already loaded.
- **Loading the hub from the leaf.** Never put `Skill(code-core)` or `Skill(test-core)` inside a
  leaf or overlay. Loading is one-directional.
- **Forgetting the DSD section.** Even an empty prose stub is mandatory — it signals to reviewers
  that overlays were considered and none exist yet.
- **Config-level overlay triggers.** Do not trigger overlays from `pyproject.toml`, `package.json`,
  or `Cargo.toml`. Use import-level patterns only (`import X`, `from X import`).
- **Skipping the dispatch row.** Without the row, all orchestrators emit "no matching skill" and
  skip the file. This produces silent no-ops that are hard to diagnose.
- **Skipping README updates.** The tables are the human-facing index. They drift fast if not updated
  alongside the skills.
- **Copying `code-shell`'s `paths:`-only pattern.** `paths:` activation was an exception for a
  language with no clean extension boundary. New languages use the dispatch table.

## See Also

This doc covers the **content overlay** architecture — DSD answers "which rules apply to _this
file_?" by detecting import patterns. A different problem has a different pattern:
[`docs/process-harness.md`](process-harness.md) covers **process skills** (project-agnostic
methodology) that need project-specific _tooling config_ — "which commands for _this project_?".
That pattern reads a harness file from a well-known path instead of dispatching on file content. The
`harden` skill is the canonical example.
