# .claude

[![CI](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml)

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: skills,
commands, agents, hooks, and settings.

## Components

### Commands

| Command                                 | Description                                                                                                                                                                                                                                                                                                                                   |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`/preflight`](commands/preflight.md)   | Automated pre-commit review pipeline. Dispatches [`code-distill`](agents/code-distill.md), [`code-mend`](agents/code-mend.md), [`/vet-code`](commands/vet-code.md), [`/vet-test`](commands/vet-test.md), and [`vet-doc`](skills/vet-doc/SKILL.md) in parallel, scores every finding, auto-fixes verified issues, and iterates up to 3 rounds. |
| [`/research`](commands/research.md)     | Enter research mode for fact-checking and verified answers                                                                                                                                                                                                                                                                                    |
| [`/vet-code`](commands/vet-code.md)     | Review code files for skill rule violations                                                                                                                                                                                                                                                                                                   |
| [`/vet-test`](commands/vet-test.md)     | Review test files for redundancy and AAA violations                                                                                                                                                                                                                                                                                           |
| [`/upgrade-py`](commands/upgrade-py.md) | Upgrade Python dependencies and sync versions                                                                                                                                                                                                                                                                                                 |
| [`/upgrade-ts`](commands/upgrade-ts.md) | Upgrade TypeScript dependencies and sync versions                                                                                                                                                                                                                                                                                             |
| [`/setup-gsd`](commands/setup-gsd.md)   | Configure GSD model overrides for a project                                                                                                                                                                                                                                                                                                   |

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
| [`write-doc`](skills/write-doc/SKILL.md)             | Documentation structure and information architecture |
| [`write-prose`](skills/write-prose/SKILL.md)         | Sentence-level clarity (Strunk's rules)              |
| [`write-commit`](skills/write-commit/SKILL.md)       | Git commit message quality                           |
| [`write-skill`](skills/write-skill/SKILL.md)         | Author and review SKILL.md files                     |
| [`write-plan`](skills/write-plan/SKILL.md)           | Multi-step implementation plans                      |
| [`humanizer`](skills/humanizer/SKILL.md)             | Detect and remove AI-generated writing patterns      |
| [`vet-doc`](skills/vet-doc/SKILL.md)                 | Review docs for structural and prose issues          |
| [`vet-skill`](skills/vet-skill/SKILL.md)             | Review SKILL.md files for quality and structure      |
| [`write-changelog`](skills/write-changelog/SKILL.md) | Keep a Changelog standard for CHANGELOG.md           |

#### Process

| Skill                                  | Description                                        |
| -------------------------------------- | -------------------------------------------------- |
| [`research`](skills/research/SKILL.md) | Fact-checking and hallucination-resistant research |

### Agents

| Agent                                    | Description                                      |
| ---------------------------------------- | ------------------------------------------------ |
| [`code-mend`](agents/code-mend.md)       | Surgical fixes at specific file:line locations   |
| [`code-distill`](agents/code-distill.md) | Reduce code complexity while preserving behavior |
| [`tdd-red`](agents/tdd-red.md)           | Context-isolated test writer (RED phase)         |
| [`tdd-green`](agents/tdd-green.md)       | Context-isolated implementer (GREEN phase)       |

### Plugins

Plugins are managed via [`plugins/manifest.json`](plugins/manifest.json) (which marketplaces and
plugins to install). The auto-generated JSON files (`installed_plugins.json`,
`known_marketplaces.json`) are gitignored since they contain volatile metadata (timestamps, absolute
paths, SHAs).

To bootstrap plugins on a fresh machine:

```sh
bash plugins/setup.sh
```

### Hooks

| Hook                                             | Description                                          |
| ------------------------------------------------ | ---------------------------------------------------- |
| [`bash-exit-guard.sh`](hooks/bash-exit-guard.sh) | Blocks proceeding when a Bash command fails          |
| [`git-safety.sh`](hooks/git-safety.sh)           | Blocks auto-push, plan file commits, destructive ops |
| [`marimo-check.sh`](hooks/marimo-check.sh)       | Validates marimo notebooks on edit                   |
| [`shiny-check.sh`](hooks/shiny-check.sh)         | Smoke-tests staged Shiny apps before commit          |
| [`worktree-safety.sh`](hooks/worktree-safety.sh) | Blocks exiting worktrees with uncommitted changes    |

## License

MIT
