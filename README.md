# .claude

[![CI](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/jeffzi/.claude/actions/workflows/pre-commit.yml)

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: skills, commands, agents,
hooks, and settings.

## Components

### Commands

| Command       | Description                                             |
| ------------- | ------------------------------------------------------- |
| `/preflight`  | Pre-commit checks with auto-fixing loop                 |
| `/vet`        | Language-specific code review (Python/Lua/Marimo/Shell) |
| `/upgrade-py` | Upgrade Python dependencies and sync versions           |

### Skills

| Skill         | Description                                                |
| ------------- | ---------------------------------------------------------- |
| `code-py`     | Python: type hints, modern syntax (3.10+), Pythonic idioms |
| `code-lua`    | Lua: LuaLS annotations, naming conventions, performance    |
| `code-marimo` | Marimo: DAG patterns, SQL-first analysis, UI reactivity    |
| `code-shell`  | Bash: strict mode, quoting, ShellCheck/shfmt compliance    |

### Agents

| Agent             | Description                                      |
| ----------------- | ------------------------------------------------ |
| `code-fixer`      | Surgical fixes at specific file:line locations   |
| `code-simplifier` | Reduce code complexity while preserving behavior |

### Hooks

| Hook              | Description                            |
| ----------------- | -------------------------------------- |
| `git-safety.sh`   | Blocks auto-push and plan file commits |
| `marimo-check.sh` | Validates marimo notebooks on edit     |

## License

MIT
