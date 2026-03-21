# .claude

[![CI](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml)

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: skills,
commands, agents, hooks, and settings.

## Components

### Commands

| Command       | Description                                         |
| ------------- | --------------------------------------------------- |
| `/preflight`  | Pre-commit checks with auto-fixing loop             |
| `/vet-code`   | Review code files for skill rule violations         |
| `/vet-test`   | Review test files for redundancy and AAA violations |
| `/upgrade-py` | Upgrade Python dependencies and sync versions       |
| `/upgrade-ts` | Upgrade TypeScript dependencies and sync versions   |

### Skills

#### Code

| Skill              | Description                                                  |
| ------------------ | ------------------------------------------------------------ |
| `code-py`          | Python: type hints, modern syntax (3.10+), Pythonic idioms   |
| `code-lua`         | Lua: LuaLS annotations, naming conventions, performance      |
| `code-marimo`      | Marimo: DAG patterns, SQL-first analysis, UI reactivity      |
| `code-shell`       | Bash: strict mode, quoting, ShellCheck/shfmt compliance      |
| `code-shiny`       | Shiny for Python: reactive logic, Express/Core mode          |
| `code-ts`          | TypeScript: strict types, modern patterns                    |
| `code-tstl`        | TypeScript-to-Lua: TSTL targeting Lua 5.1                    |
| `code-tstl-plugin` | TSTL plugins: visitor transforms, printer overrides          |
| `design-cli`       | CLI design: subcommands, flags, help text, output formatting |

#### Testing

| Skill         | Description                                               |
| ------------- | --------------------------------------------------------- |
| `tdd`         | Test-driven development orchestrator (RED-GREEN-REFACTOR) |
| `test-py`     | Python tests with pytest                                  |
| `test-ts`     | TypeScript tests with Vitest                              |
| `test-lua`    | Lua tests with busted                                     |
| `test-polars` | Polars DataFrame assertions and fixtures                  |

#### Writing

| Skill          | Description                                          |
| -------------- | ---------------------------------------------------- |
| `write-doc`    | Documentation structure and information architecture |
| `write-prose`  | Sentence-level clarity (Strunk's rules)              |
| `write-commit` | Git commit message quality                           |
| `write-skill`  | Author and review SKILL.md files                     |
| `write-plan`   | Multi-step implementation plans                      |
| `humanizer`    | Detect and remove AI-generated writing patterns      |
| `vet-doc`      | Review docs for structural and prose issues          |
| `changelog`    | Keep a Changelog standard for CHANGELOG.md           |

#### Process

| Skill                            | Description                                   |
| -------------------------------- | --------------------------------------------- |
| `verification-before-completion` | Require evidence before claiming work is done |

### Agents

| Agent          | Description                                      |
| -------------- | ------------------------------------------------ |
| `code-mend`    | Surgical fixes at specific file:line locations   |
| `code-distill` | Reduce code complexity while preserving behavior |
| `tdd-red`      | Context-isolated test writer (RED phase)         |
| `tdd-green`    | Context-isolated implementer (GREEN phase)       |

### Plugins

Plugins are managed via `plugins/manifest.json` (which marketplaces and plugins to install). The
auto-generated JSON files (`installed_plugins.json`, `known_marketplaces.json`) are gitignored since
they contain volatile metadata (timestamps, absolute paths, SHAs).

To bootstrap plugins on a fresh machine:

```sh
bash plugins/setup.sh
```

### Hooks

| Hook                 | Description                                          |
| -------------------- | ---------------------------------------------------- |
| `git-safety.sh`      | Blocks auto-push, plan file commits, destructive ops |
| `marimo-check.sh`    | Validates marimo notebooks on edit                   |
| `shiny-check.sh`     | Smoke-tests staged Shiny apps before commit          |
| `skill-loader.sh`    | Injects skill context at session start               |
| `worktree-safety.sh` | Blocks exiting worktrees with uncommitted changes    |

## License

MIT
