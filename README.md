# .claude

[![CI](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml)

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: skills,
agents, hooks, and settings.

## Components

### Skills

Some skills are synced from external repositories via
[`npx skills`](https://github.com/vercel-labs/skills). Run
[`scripts/sync-skills.sh`](scripts/sync-skills.sh) to install or update them; the script's `add`
commands are the source map.

#### Code

| Skill                                                  | Description                                                            |
| ------------------------------------------------------ | ---------------------------------------------------------------------- |
| [`code-core`](skills/code-core/SKILL.md)               | Production code principles hub (types, errors, verification, comments) |
| [`code-py`](skills/code-py/SKILL.md)                   | Python: type hints, modern syntax (3.10+), Pythonic idioms             |
| [`code-lua`](skills/code-lua/SKILL.md)                 | Lua: LuaLS annotations, naming conventions, performance                |
| [`code-marimo`](skills/code-marimo/SKILL.md)           | Marimo: DAG patterns, SQL-first analysis, UI reactivity                |
| [`code-shell`](skills/code-shell/SKILL.md)             | Bash: strict mode, quoting, ShellCheck/shfmt compliance                |
| [`code-shiny`](skills/code-shiny/SKILL.md)             | Shiny for Python: reactive logic, Express/Core mode                    |
| [`code-swift`](skills/code-swift/SKILL.md)             | Swift: strict concurrency, structured concurrency                      |
| [`code-ts`](skills/code-ts/SKILL.md)                   | TypeScript: strict types, modern patterns                              |
| [`code-tstl`](skills/code-tstl/SKILL.md)               | TypeScript-to-Lua: TSTL targeting Lua 5.1                              |
| [`code-tstl-plugin`](skills/code-tstl-plugin/SKILL.md) | TSTL plugins: visitor transforms, printer overrides                    |
| [`design-cli`](skills/design-cli/SKILL.md)             | CLI design: subcommands, flags, help text, output formatting           |

#### Testing

| Skill                                        | Description                                                                     |
| -------------------------------------------- | ------------------------------------------------------------------------------- |
| [`tdd`](skills/tdd/SKILL.md)                 | Test-driven development orchestrator (RED-GREEN-REFACTOR)                       |
| [`test-core`](skills/test-core/SKILL.md)     | Cross-language testing principles hub (AAA, merge rules, mocking anti-patterns) |
| [`test-py`](skills/test-py/SKILL.md)         | Python tests with pytest                                                        |
| [`test-ts`](skills/test-ts/SKILL.md)         | TypeScript tests with Vitest                                                    |
| [`test-lua`](skills/test-lua/SKILL.md)       | Lua tests with busted                                                           |
| [`test-polars`](skills/test-polars/SKILL.md) | Polars DataFrame assertions and fixtures                                        |
| [`test-swift`](skills/test-swift/SKILL.md)   | Swift tests with Swift Testing and XCTest                                       |

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

| Skill                                          | Description                                     |
| ---------------------------------------------- | ----------------------------------------------- |
| [`vet-code`](skills/vet-code/SKILL.md)         | Review code files for skill rule violations     |
| [`vet-test`](skills/vet-test/SKILL.md)         | Review test files for redundancy and AAA issues |
| [`vet-doc`](skills/vet-doc/SKILL.md)           | Review docs for structural and prose issues     |
| [`vet-comments`](skills/vet-comments/SKILL.md) | Standardize comment style, banners, and anchors |
| [`vet-skill`](skills/vet-skill/SKILL.md)       | Review SKILL.md files for quality and structure |

#### Process

| Skill                                                            | Description                                                                 |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------- |
| [`brainstorming`](skills/brainstorming/SKILL.md)                 | Explore intent and design space before implementing features                |
| [`build`](skills/build/SKILL.md)                                 | End-to-end feature pipeline: brainstorm → plan → TDD with quality gates     |
| [`fix`](skills/fix/SKILL.md)                                     | Root cause investigation then TDD-driven fix                                |
| [`harden`](skills/harden/SKILL.md)                               | Bug-hunting audit + DRY pass with diff-gated execution                      |
| [`preflight`](skills/preflight/SKILL.md)                         | Pre-commit review pipeline: vet, scan, auto-fix, iterate                    |
| [`receiving-code-review`](skills/receiving-code-review/SKILL.md) | Decide what to implement from review feedback (PR comments, agent findings) |
| [`plan-commit`](skills/plan-commit/SKILL.md)                     | Analyze uncommitted changes and suggest granular commits                    |
| [`investigate`](skills/investigate/SKILL.md)                     | Systematic root cause investigation — diagnosis only, no fix                |
| [`research`](skills/research/SKILL.md)                           | Fact-checking and hallucination-resistant research                          |
| [`upgrade-py`](skills/upgrade-py/SKILL.md)                       | Upgrade Python dependencies and sync versions                               |
| [`upgrade-ts`](skills/upgrade-ts/SKILL.md)                       | Upgrade TypeScript dependencies and sync versions                           |

#### Analysis

| Skill                                                          | Description                                                      |
| -------------------------------------------------------------- | ---------------------------------------------------------------- |
| [`polars`](skills/polars/SKILL.md)                             | DataFrames: lazy evaluation, parallel execution, Arrow backend   |
| [`statistical-analysis`](skills/statistical-analysis/SKILL.md) | Statistical test selection, assumption checking, APA reporting   |
| [`pymc`](skills/pymc/SKILL.md)                                 | Bayesian modeling: MCMC, variational inference, posterior checks |
| [`statsmodels`](skills/statsmodels/SKILL.md)                   | Regression, GLM, time series, mixed models, inference tables     |
| [`scikit-learn`](skills/scikit-learn/SKILL.md)                 | Classification, regression, clustering, preprocessing, pipelines |
| [`scikit-survival`](skills/scikit-survival/SKILL.md)           | Survival analysis: Cox, RSF, Brier score, censored data          |

### Agents

| Agent                                        | Description                                      |
| -------------------------------------------- | ------------------------------------------------ |
| [`bug-scanner`](agents/bug-scanner.md)       | Runtime correctness audit at specific locations  |
| [`code-mender`](agents/code-mender.md)       | Surgical fixes at specific file:line locations   |
| [`code-distiller`](agents/code-distiller.md) | Reduce code complexity while preserving behavior |
| [`tdd-cycle`](agents/tdd-cycle.md)           | Context-isolated RED-GREEN cycle agent           |

### Development Workflow

Single-session tools compose into a lightweight pipeline.

| Scope         | Tool                              | When to use                                                     |
| ------------- | --------------------------------- | --------------------------------------------------------------- |
| Bug fix       | [`/fix`](skills/fix/SKILL.md)     | Root cause unknown — investigates then drives TDD               |
| Small feature | [`/build`](skills/build/SKILL.md) | Single session — brainstorm, plan, implement with quality gates |

### Token Compression

[Headroom](https://github.com/chopratejas/headroom) reduces token usage, extending the Claude Code
Max usage cap. It runs as a local proxy that compresses requests before they reach the Anthropic API
using AST-aware code compression, JSON crushing, and KV-cache alignment (47–92% savings).

### Hooks

| Hook                                               | Description                                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------------------- |
| [`bash-exit-guard.sh`](hooks/bash-exit-guard.sh)   | Blocks proceeding when a Bash command fails                                     |
| [`config-guard.sh`](hooks/config-guard.sh)         | Protects configuration files from unintended edits                              |
| [`git-commit-guard.sh`](hooks/git-commit-guard.sh) | Blocks commit messages containing internal tooling references                   |
| [`git-guard.sh`](hooks/git-guard.sh)               | Blocks auto-push, plan file commits, destructive ops, commits during TDD cycles |
| [`git-lock-guard.sh`](hooks/git-lock-guard.sh)     | Absorbs `.git/index.lock` races from parallel agents/sessions                   |
| [`marimo-check.sh`](hooks/marimo-check.sh)         | Validates marimo notebooks on edit                                              |
| [`plan-claim-guard.sh`](hooks/plan-claim-guard.sh) | Reminds to verify plan claims before exiting plan mode                          |
| [`plan-skill-guard.sh`](hooks/plan-skill-guard.sh) | Enforces skill loading before plan mode                                         |
| [`shiny-check.sh`](hooks/shiny-check.sh)           | Smoke-tests staged Shiny apps before commit                                     |
| [`tdd-red-guard.sh`](hooks/tdd-red-guard.sh)       | Blocks reading implementation source during TDD RED phase                       |
| [`worktree-guard.sh`](hooks/worktree-guard.sh)     | Blocks exiting worktrees with uncommitted changes                               |

## License

MIT
