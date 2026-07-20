# Skill Loading

Always load the relevant skill before the corresponding action — every time, even if loaded earlier
in the same session. Plan mode context is erased on approval; never mark a skill as "already
loaded".

| Action                                    | Skill to load first                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------- |
| EnterPlanMode or writing a plan           | `Skill(write-plan)`                                                             |
| Writing code                              | `Skill(code-core)` (hub — loads the language skill via Language Dispatch below) |
| Writing tests                             | `Skill(test-core)` (hub — loads the language skill via Language Dispatch below) |
| Running TDD cycle                         | `Skill(tdd)` (hub load + RED-GREEN orchestration)                               |
| Reviewing tests                           | `Skill(vet-test)` (hub load + code-* + review checklist)                        |
| User explicitly asks to commit            | `Skill(write-commit)`                                                           |
| Bug or regression with unknown root cause | `/fix` command — investigates, then TDD                                         |
| New feature in a project with tests       | `Skill(tdd)` — start red–green cycle directly                                   |

If no matching skill exists for a language or framework, note that explicitly in the plan rather
than silently skipping the step.

## Language Dispatch for `test-*` and `code-*`

| Ext(s)                | Test skill            | Code skill | Test file patterns         |
| --------------------- | --------------------- | ---------- | -------------------------- |
| .py, .pyi             | test-py               | code-py    | `test_*.py`, `*_test.py`   |
| .ts, .tsx, .mts, .cts | test-ts               | code-ts    | `*.test.ts`, `*.spec.ts`   |
| .lua                  | test-lua              | code-lua   | `*_test.lua`, `*_spec.lua` |
| .swift                | test-swift            | code-swift | `*Tests.swift`             |
| .sh, .bash            | none (test-core only) | code-shell | `test_*.sh`                |

Overlays load automatically via base-skill Domain Skill Detection (e.g. `test-py` detects
`import polars` → `Skill(test-polars)`; `code-py` detects `import polars` → `Skill(polars)`). The
hubs `test-core` and `code-core` do not own overlay dispatch — overlays load from the base leaf. Do
not pre-compute overlays.

If a file's extension is not in the table, check `Skill(test-*)` and `Skill(code-*)` via Glob; if no
match exists, note "no matching skill" rather than guessing.
