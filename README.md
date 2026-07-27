# .claude

[![CI](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml)

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: skills,
agents, hooks, and settings.

## Components

### Skills

[`scripts/sync-skills.sh`](scripts/sync-skills.sh) syncs selected skills from external repositories
via [`npx skills`](https://github.com/vercel-labs/skills). Run it to install or update them; the
script's `add` commands are the source map.

#### Code

| Skill                                                  | Description                                                                      |
| ------------------------------------------------------ | -------------------------------------------------------------------------------- |
| [`code-core`](skills/code-core/SKILL.md)               | Production code principles hub (types, errors, verification, comments)           |
| [`code-py`](skills/code-py/SKILL.md)                   | Python: type hints, modern syntax (3.10+), Pythonic idioms                       |
| [`code-lua`](skills/code-lua/SKILL.md)                 | Lua: LuaLS annotations, naming conventions, performance                          |
| [`code-marimo`](skills/code-marimo/SKILL.md)           | Marimo: directed acyclic graph (DAG) patterns, SQL-first analysis, UI reactivity |
| [`code-shell`](skills/code-shell/SKILL.md)             | Bash: strict mode, quoting, ShellCheck/shfmt compliance                          |
| [`code-shiny`](skills/code-shiny/SKILL.md)             | Shiny for Python: reactive logic, Express/Core mode                              |
| [`code-swift`](skills/code-swift/SKILL.md)             | Swift: strict concurrency, structured concurrency                                |
| [`code-ts`](skills/code-ts/SKILL.md)                   | TypeScript: strict types, modern patterns                                        |
| [`code-tstl`](skills/code-tstl/SKILL.md)               | TypeScript-to-Lua: TSTL targeting Lua 5.1                                        |
| [`code-tstl-plugin`](skills/code-tstl-plugin/SKILL.md) | TSTL plugins: visitor transforms, printer overrides                              |
| [`design-cli`](skills/design-cli/SKILL.md)             | CLI design: subcommands, flags, help text, output formatting                     |

#### Testing

| Skill                                        | Description                                                                                    |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [`tdd`](skills/tdd/SKILL.md)                 | Test-driven development orchestrator (RED-GREEN-REFACTOR)                                      |
| [`test-core`](skills/test-core/SKILL.md)     | Cross-language testing principles hub (Arrange-Act-Assert, merge rules, mocking anti-patterns) |
| [`test-py`](skills/test-py/SKILL.md)         | Python tests with pytest                                                                       |
| [`test-ts`](skills/test-ts/SKILL.md)         | TypeScript tests with Vitest                                                                   |
| [`test-lua`](skills/test-lua/SKILL.md)       | Lua tests with busted                                                                          |
| [`test-polars`](skills/test-polars/SKILL.md) | Polars DataFrame assertions and fixtures                                                       |
| [`test-swift`](skills/test-swift/SKILL.md)   | Swift tests with Swift Testing and XCTest                                                      |
| [`stryker-js`](skills/stryker-js/SKILL.md)   | Mutation testing with StrykerJS for JS/TS projects                                             |

> To add a language skill pair (`code-*` and `test-*`) or library overlay, follow
> [`docs/languages.md`](docs/languages.md).

#### Writing

| Skill                                                                  | Description                                                        |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------ |
| [`write-agent`](skills/write-agent/SKILL.md)                           | Author and review agent definition files                           |
| [`write-doc`](skills/write-doc/SKILL.md)                               | Documentation structure and information architecture               |
| [`write-prose`](skills/write-prose/SKILL.md)                           | Sentence-level clarity (Strunk's rules)                            |
| [`write-commit`](skills/write-commit/SKILL.md)                         | Git commit message quality                                         |
| [`write-skill`](skills/write-skill/SKILL.md)                           | Author and review SKILL.md files                                   |
| [`write-plan`](skills/write-plan/SKILL.md)                             | Multi-step implementation plans                                    |
| [`write-changelog`](skills/write-changelog/SKILL.md)                   | Keep a Changelog standard for CHANGELOG.md                         |
| [`humanizer`](skills/humanizer/SKILL.md)                               | Remove AI writing patterns from prose                              |
| [`literature-review`](skills/literature-review/SKILL.md)               | Systematic literature reviews across academic databases            |
| [`markdown-mermaid-writing`](skills/markdown-mermaid-writing/SKILL.md) | Markdown and Mermaid style guides, templates, and 24 diagram types |
| [`paper-lookup`](skills/paper-lookup/SKILL.md)                         | Search 10 academic databases by keyword, DOI, or author            |

#### Review

| Skill                                                        | Description                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------------- |
| [`revise-code`](skills/revise-code/SKILL.md)                 | Review code for idiom/type/structure violations, then fix           |
| [`revise-test`](skills/revise-test/SKILL.md)                 | Review tests for redundancy and Arrange-Act-Assert issues, then fix |
| [`revise-doc`](skills/revise-doc/SKILL.md)                   | Review docs for structural and prose issues, then fix               |
| [`revise-comments`](skills/revise-comments/SKILL.md)         | Review comment style, banners, and anchors, then fix                |
| [`revise-skill`](skills/revise-skill/SKILL.md)               | Review SKILL.md files for quality and structure, then fix           |
| [`scan-bug`](skills/scan-bug/SKILL.md)                       | Scan for runtime bugs: null access, leaks, races, logic errors      |
| [`scan-simplification`](skills/scan-simplification/SKILL.md) | Scan for over-engineering and unneeded complexity                   |

Each `/revise-*` command dispatches the matching read-only `vet-*` agent, then applies what it
finds. Dispatch the agent directly when you want findings without edits.

#### Process

| Skill                                                            | Description                                                                    |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| [`brainstorming`](skills/brainstorming/SKILL.md)                 | Explore intent and design space before implementing features                   |
| [`build`](skills/build/SKILL.md)                                 | End-to-end feature pipeline: brainstorm → plan → TDD with quality gates        |
| [`fix`](skills/fix/SKILL.md)                                     | Root cause investigation then TDD-driven fix                                   |
| [`harden`](skills/harden/SKILL.md)                               | Bug-hunting audit + Don't Repeat Yourself (DRY) pass with diff-gated execution |
| [`preflight`](skills/preflight/SKILL.md)                         | Gated pre-commit pipeline: review, auto-fix, verify, restore on red            |
| [`receiving-code-review`](skills/receiving-code-review/SKILL.md) | Decide what to implement from review feedback (PR comments, agent findings)    |
| [`plan-commit`](skills/plan-commit/SKILL.md)                     | Analyze uncommitted changes and suggest granular commits                       |
| [`investigate`](skills/investigate/SKILL.md)                     | Systematic root cause investigation — diagnosis only, no fix                   |
| [`research`](skills/research/SKILL.md)                           | Fact-checking and hallucination-resistant research                             |
| [`upgrade-py`](skills/upgrade-py/SKILL.md)                       | Upgrade Python dependencies and sync versions                                  |
| [`upgrade-ts`](skills/upgrade-ts/SKILL.md)                       | Upgrade TypeScript dependencies and sync versions                              |
| [`setup-ts`](skills/setup-ts/SKILL.md)                           | Scaffold or update shared TS tooling config (oxlint, tsconfig, etc.)           |
| [`distill-code`](skills/distill-code/SKILL.md)                   | Reduce code complexity after implementation (nesting, duplication, naming)     |
| [`fallow`](skills/fallow/SKILL.md)                               | Codebase intelligence: risk, duplication, complexity, dead code (TS/JS)        |

#### Analysis

| Skill                                                          | Description                                                                                 |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [`polars`](skills/polars/SKILL.md)                             | DataFrames: lazy evaluation, parallel execution, Arrow backend                              |
| [`statistical-analysis`](skills/statistical-analysis/SKILL.md) | Statistical test selection, assumption checking, APA-style reporting                        |
| [`pymc`](skills/pymc/SKILL.md)                                 | Bayesian modeling: Markov chain Monte Carlo (MCMC), variational inference, posterior checks |
| [`statsmodels`](skills/statsmodels/SKILL.md)                   | Regression, generalized linear models (GLM), time series, mixed models, inference tables    |
| [`scikit-learn`](skills/scikit-learn/SKILL.md)                 | Classification, regression, clustering, preprocessing, pipelines                            |
| [`scikit-survival`](skills/scikit-survival/SKILL.md)           | Survival analysis: Cox, random survival forest (RSF), Brier score, censored data            |

### Agents

| Agent                                                        | Description                                             |
| ------------------------------------------------------------ | ------------------------------------------------------- |
| [`bug-scanner`](agents/bug-scanner.md)                       | Runtime correctness audit at specific locations         |
| [`simplification-scanner`](agents/simplification-scanner.md) | Dead code, single-use abstractions, stdlib replacements |
| [`distill-scanner`](agents/distill-scanner.md)               | Read-only distillation review: nesting, duplication     |
| [`vet-code`](agents/vet-code.md)                             | Review code against idiom, type, and structure rules    |
| [`vet-test`](agents/vet-test.md)                             | Review tests for redundancy, AAA, and drift             |
| [`vet-doc`](agents/vet-doc.md)                               | Review docs for structure, prose, accessibility         |
| [`vet-comments`](agents/vet-comments.md)                     | Review comment style, banners, and anchors              |
| [`vet-skill`](agents/vet-skill.md)                           | Review SKILL.md files for quality and structure         |
| [`code-mender`](agents/code-mender.md)                       | Surgical fixes at specific file:line locations          |
| [`code-distiller`](agents/code-distiller.md)                 | Reduce code complexity while preserving behavior        |
| [`tdd-cycle`](agents/tdd-cycle.md)                           | Context-isolated RED-GREEN cycle agent                  |
| [`claim-reviewer`](agents/claim-reviewer.md)                 | Verify claims against the codebase independently        |

The five `vet-*` agents are read-only: no `Edit`, `Write`, or `Bash`. They return `### Finding N`
blocks, each carrying a confidence score (0/25/50/80/100) and a domain impact tag. The paired
`revise-*` skill gates on the score, orders the fix queue by impact, and applies the fixes.

### Rules

Always-on rules live in `rules/` and are auto-loaded into every conversation. Rules with `paths:`
frontmatter activate only when matching files are in context.

| Rule                                                    | Description                                                    |
| ------------------------------------------------------- | -------------------------------------------------------------- |
| [`code-exploration`](rules/code-exploration.md)         | Orient before drilling: structure-first reading policy         |
| [`no-cross-repo-edits`](rules/no-cross-repo-edits.md)   | Block edits outside the session's git root                     |
| [`no-destructive-ops`](rules/no-destructive-ops.md)     | Block commands that discard uncommitted work                   |
| [`receiving-feedback`](rules/receiving-feedback.md)     | Verify feedback before implementing; no performative agreement |
| [`skill-loading`](rules/skill-loading.md)               | Mandatory skill loading before every matching action           |
| [`decision-policy`](rules/decision-policy.md)           | Durable fix by default; ask only when the answer changes work  |
| [`no-unilateral-action`](rules/no-unilateral-action.md) | Questions route through the user                               |
| [`no-unrequested-edits`](rules/no-unrequested-edits.md) | Report first, edit only on explicit request                    |

## Development Workflow

The two most common entry points for single-session work:

| Scope         | Tool                              | When to use                                                     |
| ------------- | --------------------------------- | --------------------------------------------------------------- |
| Bug fix       | [`/fix`](skills/fix/SKILL.md)     | Root cause unknown — investigates then drives TDD               |
| Small feature | [`/build`](skills/build/SKILL.md) | Single session — brainstorm, plan, implement with quality gates |

See the [Process](#process) skills table for additional workflows (`/harden`, `/preflight`,
`/distill-code`, and others).

## Tooling

### Status Line

[`scripts/statusline.sh`](scripts/statusline.sh) renders a custom status line showing model name,
project directory, context window usage bar, and rate limit pacing. Rate limits display the 5-hour
window as a countdown (`⏳2h`) and the 7-day window as an absolute reset date (`⏳Jul12 09:00`).
Pace emoji (🔥 / 🐢) appear above 50% usage when the burn rate diverges from an even linear spend.

```text
.claude │ Opus 4.6 ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░ 45% │ 5h:72% (🔥 ⏳2h) │ 7d:89% (🐢 ⏳Jul13 09:00)
```

### Hooks

| Hook                                               | Description                                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------------------- |
| [`bash-exit-guard.sh`](hooks/bash-exit-guard.sh)   | Blocks proceeding when a Bash command fails                                     |
| [`git-commit-guard.sh`](hooks/git-commit-guard.sh) | Blocks commit messages containing internal tooling references                   |
| [`git-guard.sh`](hooks/git-guard.sh)               | Blocks auto-push, plan file commits, destructive ops, commits during TDD cycles |
| [`git-lock-guard.sh`](hooks/git-lock-guard.sh)     | Absorbs `.git/index.lock` races from parallel agents/sessions                   |
| [`marimo-check.sh`](hooks/marimo-check.sh)         | Validates marimo notebooks on edit                                              |
| [`plan-claim-guard.sh`](hooks/plan-claim-guard.sh) | Reminds to verify plan claims before exiting plan mode                          |
| [`plan-skill-guard.sh`](hooks/plan-skill-guard.sh) | Enforces skill loading before plan mode                                         |
| [`shiny-check.sh`](hooks/shiny-check.sh)           | Smoke-tests staged Shiny apps before commit                                     |
| [`tdd-red-guard.sh`](hooks/tdd-red-guard.sh)       | Blocks reading implementation source during TDD RED phase                       |
| [`worktree-guard.sh`](hooks/worktree-guard.sh)     | Blocks exiting worktrees with uncommitted changes                               |
| [`collab-reminder.sh`](hooks/collab-reminder.sh)   | Re-injects propose-decisions / answer-first policy on every prompt              |

## Configuration Notes

### Where `model` and `effort` take effect

Skills and agents resolve these two fields differently, and the difference decides whether a
declaration is worth writing at all.

**Skill frontmatter is slash-path only.** `model` and `effort` apply when the user types
`/skill-name`. Loaded through the `Skill()` tool, or reached inside a subagent, both are inert — the
surrounding turn governs. So the hubs and language leaves (`code-core`, `test-core`, `code-py`, …)
declare neither: they are only ever loaded, never invoked. A live declaration overrides the user's
`/model` choice for the whole turn, so it needs a stated reason.

The upstream docs describe both fields as applying "when this skill is active", with no
invocation-path qualifier. That is why this is written down here.

**Agent frontmatter is live on every dispatch**, but four things can set it. First present wins:

1. `CLAUDE_CODE_SUBAGENT_MODEL` (environment or `settings.json` `env`)
2. The `model` parameter on the dispatching `Agent` call
3. The agent's `model:` frontmatter
4. The session model

The env var outranks even an explicit per-call value — a stray `CLAUDE_CODE_SUBAGENT_MODEL: haiku`
downgrades every agent while the frontmatter still reads `opus`. Callers that want an agent to
govern its own tier pass no `model` parameter.

Authoring rules live in [`write-skill`](skills/write-skill/SKILL.md) and
[`write-agent`](skills/write-agent/SKILL.md).

## License

MIT
