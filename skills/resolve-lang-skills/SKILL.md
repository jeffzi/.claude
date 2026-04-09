---
name: resolve-lang-skills
description: >
  Use when resolving which code-*/test-* skills apply to a set of files before dispatching
  language-specific agents or loading language skills. Not user-invocable — loaded by orchestrator
  skills.
user-invocable: false
model: haiku
effort: low
---

# Language Skill Resolution

## Naming Convention

Skill names follow `code-{lang}` / `test-{lang}`. Derive lang from file extension:

| Extension(s)           | Lang    |
| ---------------------- | ------- |
| `.py`                  | `py`    |
| `.ts`, `.tsx`          | `ts`    |
| `.lua`                 | `lua`   |
| `.swift`               | `swift` |
| `.sh`, `.bash`, `.zsh` | `shell` |

Unknown extension → `none` for both skills.

## Test Skill Resolution

`TEST_SKILL` is derived from the **language of files present** (source or test). A test skill
applies whenever files of that language exist in the target scope — not only when test files already
exist.

| Lang    | Test file patterns (informational)                       |
| ------- | -------------------------------------------------------- |
| `py`    | `test_*.py`, `*_test.py`, `tests/**/*.py`, `conftest.py` |
| `ts`    | `*.test.ts`, `*.test.tsx`, `*.spec.ts`, `*.spec.tsx`     |
| `lua`   | `*_test.lua`, `spec/**/*.lua`                            |
| `swift` | `*Tests.swift`                                           |

**Rule**: if any file of a given lang is present, set `TEST_SKILL: test-{lang}`. `shell` has no test
skill → `TEST_SKILL: none` when only shell files are present.

## Project Overlay Detection

Run **once per project root** — not per file. Read config files; prepend active overlays to
CODE_SKILLS or TEST_SKILLS (most-specific first).

| Config file      | Signal                      | Overlay       | Prepend to  |
| ---------------- | --------------------------- | ------------- | ----------- |
| `pyproject.toml` | `marimo` in deps            | `code-marimo` | CODE_SKILLS |
| `pyproject.toml` | `shiny` in deps             | `code-shiny`  | CODE_SKILLS |
| `pyproject.toml` | `polars` in deps            | `test-polars` | TEST_SKILLS |
| `tsconfig.json`  | `tstl` key present          | `code-tstl`   | CODE_SKILLS |
| `package.json`   | `typescript-to-lua` in deps | `code-tstl`   | CODE_SKILLS |

**Overlay detection is only needed when passing skill names as strings to subagents** (e.g., the tdd
path). Skills loaded via `Skill()` get overlays automatically through base skill Domain Skill
Detection — no pre-detection needed.

## Common Mistakes

| Mistake                                                 | Fix                                                                                                      |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Running overlay detection for `Skill()` loads           | Unnecessary — overlays apply automatically; only needed when passing skill names as strings to subagents |
| Detecting overlays per-file instead of per-project-root | Run once per project root, cache the result                                                              |
