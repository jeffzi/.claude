# .claude

[![CI](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml)

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: skills,
agents, hooks, and settings.

## Components

### Skills

#### Code

| Skill                                                  | Description                                                  |
| ------------------------------------------------------ | ------------------------------------------------------------ |
| [`code-py`](skills/code-py/SKILL.md)                   | Python: type hints, modern syntax (3.10+), Pythonic idioms   |
| [`code-lua`](skills/code-lua/SKILL.md)                 | Lua: LuaLS annotations, naming conventions, performance      |
| [`code-marimo`](skills/code-marimo/SKILL.md)           | Marimo: DAG patterns, SQL-first analysis, UI reactivity      |
| [`code-shell`](skills/code-shell/SKILL.md)             | Bash: strict mode, quoting, ShellCheck/shfmt compliance      |
| [`code-shiny`](skills/code-shiny/SKILL.md)             | Shiny for Python: reactive logic, Express/Core mode          |
| [`code-swift`](skills/code-swift/SKILL.md)             | Swift: strict concurrency, structured concurrency            |
| [`code-ts`](skills/code-ts/SKILL.md)                   | TypeScript: strict types, modern patterns                    |
| [`code-tstl`](skills/code-tstl/SKILL.md)               | TypeScript-to-Lua: TSTL targeting Lua 5.1                    |
| [`code-tstl-plugin`](skills/code-tstl-plugin/SKILL.md) | TSTL plugins: visitor transforms, printer overrides          |
| [`design-cli`](skills/design-cli/SKILL.md)             | CLI design: subcommands, flags, help text, output formatting |

#### Testing

| Skill                                        | Description                                               |
| -------------------------------------------- | --------------------------------------------------------- |
| [`tdd`](skills/tdd/SKILL.md)                 | Test-driven development orchestrator (RED-GREEN-REFACTOR) |
| [`test-py`](skills/test-py/SKILL.md)         | Python tests with pytest                                  |
| [`test-ts`](skills/test-ts/SKILL.md)         | TypeScript tests with Vitest                              |
| [`test-lua`](skills/test-lua/SKILL.md)       | Lua tests with busted                                     |
| [`test-polars`](skills/test-polars/SKILL.md) | Polars DataFrame assertions and fixtures                  |
| [`test-swift`](skills/test-swift/SKILL.md)   | Swift tests with Swift Testing and XCTest                 |

#### Writing

| Skill                                                | Description                                          |
| ---------------------------------------------------- | ---------------------------------------------------- |
| [`write-agent`](skills/write-agent/SKILL.md)         | Author and review agent definition files             |
| [`write-doc`](skills/write-doc/SKILL.md)             | Documentation structure and information architecture |
| [`write-prose`](skills/write-prose/SKILL.md)         | Sentence-level clarity (Strunk's rules)              |
| [`write-commit`](skills/write-commit/SKILL.md)       | Git commit message quality                           |
| [`write-skill`](skills/write-skill/SKILL.md)         | Author and review SKILL.md files                     |
| [`write-plan`](skills/write-plan/SKILL.md)           | Multi-step implementation plans                      |
| [`write-changelog`](skills/write-changelog/SKILL.md) | Keep a Changelog standard for CHANGELOG.md           |

#### Review

| Skill                                    | Description                                     |
| ---------------------------------------- | ----------------------------------------------- |
| [`vet-code`](skills/vet-code/SKILL.md)   | Review code files for skill rule violations     |
| [`vet-test`](skills/vet-test/SKILL.md)   | Review test files for redundancy and AAA issues |
| [`vet-doc`](skills/vet-doc/SKILL.md)     | Review docs for structural and prose issues     |
| [`vet-skill`](skills/vet-skill/SKILL.md) | Review SKILL.md files for quality and structure |

#### Process

| Skill                                                        | Description                                                             |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [`build`](skills/build/SKILL.md)                             | End-to-end feature pipeline: brainstorm → plan → TDD with quality gates |
| [`fix`](skills/fix/SKILL.md)                                 | Root cause investigation then TDD-driven fix                            |
| [`preflight`](skills/preflight/SKILL.md)                     | Pre-commit review pipeline: vet, scan, auto-fix, iterate                |
| [`plan-commit`](skills/plan-commit/SKILL.md)                 | Analyze uncommitted changes and suggest granular commits                |
| [`investigate`](skills/investigate/SKILL.md)                 | Systematic root cause investigation — diagnosis only, no fix            |
| [`research`](skills/research/SKILL.md)                       | Fact-checking and hallucination-resistant research                      |
| [`resolve-lang-skills`](skills/resolve-lang-skills/SKILL.md) | Select appropriate code-_/test-_ skills for a given language            |
| [`setup-gsd`](skills/setup-gsd/SKILL.md)                     | Configure GSD model overrides for a project                             |
| [`upgrade-py`](skills/upgrade-py/SKILL.md)                   | Upgrade Python dependencies and sync versions                           |
| [`upgrade-ts`](skills/upgrade-ts/SKILL.md)                   | Upgrade TypeScript dependencies and sync versions                       |

### Agents

| Agent                                    | Description                                      |
| ---------------------------------------- | ------------------------------------------------ |
| [`bug-scanner`](agents/bug-scanner.md)   | Runtime correctness audit at specific locations  |
| [`code-mend`](agents/code-mend.md)       | Surgical fixes at specific file:line locations   |
| [`code-distill`](agents/code-distill.md) | Reduce code complexity while preserving behavior |
| [`tdd-cycle`](agents/tdd-cycle.md)       | Context-isolated RED-GREEN cycle agent           |

### Development Workflow

Single-session tools compose into a lightweight pipeline. Escalate to GSD when a feature spans
multiple sessions or needs persistent planning state.

| Scope         | Tool                                              | When to use                                                     |
| ------------- | ------------------------------------------------- | --------------------------------------------------------------- |
| Bug fix       | [`/fix`](skills/fix/SKILL.md)                     | Root cause unknown — investigates then drives TDD               |
| Small feature | [`/build`](skills/build/SKILL.md)                 | Single session — brainstorm, plan, implement with quality gates |
| Large feature | [GSD](https://github.com/gsd-build/get-shit-done) | Multi-session — disk-persistent planning, cross-session context |

### GSD (Get Shit Done)

[GSD](https://github.com/gsd-build/get-shit-done) is installed as a plugin for structured project
execution — milestone planning, phased delivery, parallel workstreams, and verification. It provides
its own skills, commands, and agents (prefixed with `gsd:`/`gsd-`).

### Token Compression

[Headroom](https://github.com/chopratejas/headroom) reduces token usage, stretching the Claude Code
Max usage cap. It runs as a local proxy that compresses requests before they reach the Anthropic API
using AST-aware code compression, JSON crushing, and KV-cache alignment (47–92% savings).

### Hooks

| Hook                                               | Description                                          |
| -------------------------------------------------- | ---------------------------------------------------- |
| [`bash-exit-guard.sh`](hooks/bash-exit-guard.sh)   | Blocks proceeding when a Bash command fails          |
| [`config-guard.sh`](hooks/config-guard.sh)         | Protects configuration files from unintended edits   |
| [`desktop-notify.sh`](hooks/desktop-notify.sh)     | macOS notification when Claude finishes responding   |
| [`git-guard.sh`](hooks/git-guard.sh)               | Blocks auto-push, plan file commits, destructive ops |
| [`marimo-check.sh`](hooks/marimo-check.sh)         | Validates marimo notebooks on edit                   |
| [`plan-skill-guard.sh`](hooks/plan-skill-guard.sh) | Enforces skill loading before plan mode              |
| [`shiny-check.sh`](hooks/shiny-check.sh)           | Smoke-tests staged Shiny apps before commit          |
| [`worktree-guard.sh`](hooks/worktree-guard.sh)     | Blocks exiting worktrees with uncommitted changes    |

## License

MIT
