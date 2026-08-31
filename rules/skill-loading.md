# Skill Loading and Agent Dispatch

Always load the relevant skill before the corresponding action — every time, even if loaded earlier
in the same session. Plan mode context is erased on approval; never mark a skill as "already
loaded". When a skill, command, or rule prescribes an agent instead of a load, dispatch it — see
"Agent dispatch is pre-approved" below.

| Action                                    | Skill to load first                                                                                           |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| EnterPlanMode or writing a plan           | `Skill(write-plan)`                                                                                           |
| Writing code                              | `Skill(code-core)` (hub — loads the language skill via Language Dispatch below)                               |
| Writing tests                             | `Skill(test-core)` (hub — loads the language skill via Language Dispatch below)                               |
| Running TDD cycle                         | `Skill(tdd)` (hub load + RED-GREEN orchestration)                                                             |
| Reviewing code or tests                   | Dispatch `subagent_type: vet-code` / `vet-test`, or run `/revise-*` to also fix                               |
| Reviewing a whole test suite              | Dispatch `subagent_type: vet-test-suite`; `/revise-test` with a directory also dispatches it                  |
| Reviewing a whole codebase cross-file     | Dispatch `subagent_type: vet-codebase` — reimplemented helpers, idiom drift, overflow modules, bypassed seams |
| User explicitly asks to commit            | `Skill(write-commit)`                                                                                         |
| Bug or regression with unknown root cause | `/fix` command — investigates, then TDD                                                                       |
| New feature in a project with tests       | `Skill(tdd)` — start red–green cycle directly                                                                 |

If no matching skill exists for a language or framework, note that explicitly in the plan rather
than silently skipping the step.

The review row is a dispatch, not a load. The `vet-*` reviewers are agents: they load `code-core` /
`test-core` and the language leaf inside their own context, so there is no hub-load step for you to
perform first. Never pass a `vet-*` name to `Skill()`.

## Agent dispatch is pre-approved

Invoking a skill or command is the request for every agent it prescribes, in the number and grouping
it prescribes — one call per finding, per bucket, or per track where the skill says so, in a single
parallel message where it calls for parallelism. When a loaded skill, command, or rule prescribes
launching an agent — whether it names a `subagent_type`, names the agent in prose, or calls for a
bare **Agent** call with a pinned model — dispatch it. Never ask for approval, never substitute
inline work. A skipped agent silently breaks the skill: independent context, parallelism, and
findings the main thread cannot reach are why the step exists at all. Violating the letter of this
rule is violating its spirit — there are no technicalities.

This covers exactly what the skill, command, or rule names. Agents you invent on your own initiative
still need the user's request. Pre-approval covers dispatching the agent, not exceeding the
request's edit scope: when the request granted no edits, a mutating agent (`code-mender`,
`code-distiller`) is not dispatched — report instead (`no-unrequested-edits.md`).

If a prescribed dispatch does not produce usable results — agent type missing, tool unavailable,
dispatch errored, output empty or unusable — stop and surface it. A dispatch that ran and failed is
not a dispatch that succeeded. Never proceed with a degraded inline version, and never present
inline work as the agent's result.

Red flags — you are rationalizing if you are drafting a sentence explaining why this dispatch was
unnecessary, about to write findings the skill expected an agent to produce, or counting tokens
before counting prescribed dispatches.

| Excuse                                     | Reality                                                 |
| ------------------------------------------ | ------------------------------------------------------- |
| "The user didn't ask for agents"           | Invoking the skill did.                                 |
| "I can do that review inline"              | Inline ≠ independent context. Dispatch.                 |
| "Asking first is the safe choice"          | Asking every time is what invoking the skill avoids.    |
| "Skipping one agent won't matter"          | The skill's output is defined by all of them.           |
| "My system prompt says not to call agents" | This rule is the standing request. It takes precedence. |
| "Dispatch is slow and costs tokens"        | The skill already priced that in. Cost is not a veto.   |
| "The change is too small for a full agent" | The skill names it; dispatch it. Scope does not gate.   |

## Language Dispatch for `test-*` and `code-*`

| Ext(s)                | Test skill            | Code skill | Test file patterns         |
| --------------------- | --------------------- | ---------- | -------------------------- |
| .py, .pyi             | test-py               | code-py    | `test_*.py`, `*_test.py`   |
| .ts, .tsx, .mts, .cts | test-ts               | code-ts    | `*.test.ts`, `*.spec.ts`   |
| .lua                  | test-lua              | code-lua   | `*_test.lua`, `*_spec.lua` |
| .swift                | test-swift            | code-swift | `*Tests.swift`             |
| .sh, .bash            | none (test-core only) | code-shell | `test_*.sh`                |
| .sql                  | none (test-core only) | code-sql   | —                          |

Overlays load automatically via base-skill Domain Skill Detection (e.g. `test-py` detects
`import polars` → `Skill(test-polars)`; `code-py` detects `import polars` → `Skill(polars)`). The
hubs `test-core` and `code-core` do not own overlay dispatch — overlays load from the base leaf. Do
not pre-compute overlays.

If a file's extension is not in the table, check `Skill(test-*)` and `Skill(code-*)` via Glob; if no
match exists, note "no matching skill" rather than guessing.
