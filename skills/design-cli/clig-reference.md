# CLI Design Reference

> Condensed actionable reference from [clig.dev](https://clig.dev). Tables, rules, and examples for
> quick lookup during CLI design and review. For the decision framework and checklist, see SKILL.md.

## Exit Codes

| Code  | Meaning            | Example                              |
| ----- | ------------------ | ------------------------------------ |
| 0     | Success            | Command completed normally           |
| 1     | General error      | Runtime failure, bad input           |
| 2     | Usage error        | Invalid flags, missing required args |
| 126   | Cannot execute     | Permission denied on target binary   |
| 127   | Command not found  | Typo in command name                 |
| 128+N | Killed by signal N | 130 = Ctrl-C (SIGINT), 137 = SIGKILL |

## Standard Flag Names

Use these when they fit. Users expect them.

| Short | Long         | Meaning                                                        |
| ----- | ------------ | -------------------------------------------------------------- |
| `-a`  | `--all`      | All items (e.g. `ps -a`, `fetchmail -a`)                       |
| `-d`  | `--debug`    | Show debugging output                                          |
| `-f`  | `--force`    | Skip confirmation / force destructive action                   |
|       | `--json`     | Machine-readable JSON output                                   |
| `-h`  | `--help`     | Show help text (never overload this)                           |
| `-n`  | `--dry-run`  | Show what would happen without doing it                        |
|       | `--no-input` | Disable all interactive prompts                                |
| `-o`  | `--output`   | Output file path                                               |
| `-p`  | `--port`     | Port number                                                    |
| `-q`  | `--quiet`    | Suppress non-essential output                                  |
| `-u`  | `--user`     | Username                                                       |
| `-v`  |              | Ambiguous: can mean verbose or version. Prefer `-d` for debug. |
|       | `--version`  | Show version and exit                                          |
|       | `--no-color` | Disable colored output                                         |
|       | `--plain`    | Tabular text output for grep/awk                               |

## Help Text Rules

1. Show full help on `-h` and `--help` (ignore other flags when help is requested).
2. Show concise help when run with no args (if args are required): description, 1-2 examples,
   pointer to `--help`.
3. Lead with examples, not flag lists. Show common complex uses first.
4. Display most common flags/commands at the top.
5. Use bold/formatting for scannable headings (terminal-independent).
6. Provide a support/feedback path (URL or GitHub link).
7. Link to web docs (deep-link subcommand-specific pages when possible).

**Good example (jq):**

```text
$ jq
jq - commandline JSON processor [version 1.6]

Usage:    jq [options] <jq filter> [file...]

jq is a tool for processing JSON inputs, applying the given filter
to its JSON text inputs and producing the filter's results as JSON
on standard output.

Example:
    $ echo '{"foo": 0}' | jq .
    {
        "foo": 0
    }

For a listing of options, use jq --help.
```

## Output Design

### Human vs Machine Rules

- stdout for data, stderr for messages/logs/errors.
- Detect TTY: human-friendly formatting when interactive, machine-friendly when piped.
- Display output on success, but keep it brief. Report state changes explicitly.
- Use a pager (`less -FIRX`) for large output when stdout is a TTY.
- Suggest next commands when relevant (like `git status` does).

### Color Rules

Disable color when ANY of these is true:

| Condition                 | Check                                     |
| ------------------------- | ----------------------------------------- |
| stdout is not a TTY       | `sys.stdout.isatty()` is False            |
| `NO_COLOR` env var is set | Non-empty value, regardless of content    |
| `TERM=dumb`               | Terminal doesn't support escape sequences |
| `--no-color` flag passed  | Explicit user override                    |
| `MYAPP_NO_COLOR` set      | App-specific override (optional)          |

Use `FORCE_COLOR` to enable color and skip detection logic.

### Progress and Pager

- Print something within 100ms. Don't hang silently.
- Show progress bars/spinners for operations >1s. Show estimated time if possible.
- No animations when stdout is not a TTY (prevents CI log Christmas trees).
- Use a pager only when stdout is a TTY.

## Error Design

1. Catch errors and rewrite them for humans: "Can't write to file.txt. You might need to run
   `chmod +w file.txt`."
2. Put the most important information last (where the eye goes).
3. Use red sparingly and intentionally.
4. Hide stack traces by default; show with `--debug` / `--verbose`.
5. For unexpected errors: write debug log to file, show how to submit a bug report.
6. Group multiple errors of the same type under one header (signal-to-noise).

**Bad:**

```text
Traceback (most recent call last):
  File "cli.py", line 42, in main
    ...
FileNotFoundError: [Errno 2] No such file or directory: 'config.yml'
```

**Good:**

```text
Error: Config file not found: config.yml
  Looked in: ./config.yml, ~/.config/myapp/config.yml
  Run `myapp init` to create a default config.
```

## Arguments and Flags

1. **Prefer flags to args.** Flags are self-documenting and order-independent.
2. **Every flag gets a `--long-form`.** Short forms only for common, top-level flags.
3. **Use standard names** (see table above).
4. **Make flags order-independent.** `mycmd --foo subcmd` and `mycmd subcmd --foo` should both work.
5. **Multiple args for same thing are fine:** `rm file1.txt file2.txt *.log`
6. **Two+ args for different things is a smell.** Exception: `cp <source> <dest>`.
7. **Support `-` for stdin/stdout** where files are expected.
8. **Never accept secrets via flags.** Use `--password-file` or read from stdin.

### Dangerous Operations — Severity Guide

| Severity | Example                              | Response                                              |
| -------- | ------------------------------------ | ----------------------------------------------------- |
| Mild     | Delete a single file                 | Optional confirmation                                 |
| Moderate | Delete a directory / remote resource | Prompt for `y/n`, offer `--dry-run`                   |
| Severe   | Delete entire app/server             | Require typing the resource name, or `--confirm=name` |

## Subcommands

1. Use consistent verb naming across object types: `noun verb` (e.g. `docker container create`).
2. Be consistent with verbs. Don't mix `delete` and `remove` for the same action.
3. No ambiguous names. Don't have both `update` and `upgrade`.
4. No catch-all subcommand: if first arg isn't a known subcommand, error — don't guess.
5. No arbitrary abbreviations. Aliases are fine, but must be explicit and stable.

## Interactivity

1. Prompt only when stdin is a TTY. In scripts, require flags instead.
2. `--no-input` disables all prompts. Fail with a message saying which flag to pass.
3. Hide password input (disable echo).
4. Ctrl-C exits immediately. Second Ctrl-C skips cleanup. Explain what happens.
5. Make escape path clear. Don't be like vim.

## Configuration Precedence

Highest to lowest priority:

| Priority | Source                | Example                       |
| -------- | --------------------- | ----------------------------- |
| 1        | Flags                 | `--port 8080`                 |
| 2        | Environment variables | `MYAPP_PORT=8080`             |
| 3        | Project-level config  | `.myapp.toml` in project root |
| 4        | User-level config     | `~/.config/myapp/config.toml` |
| 5        | System-wide config    | `/etc/myapp/config.toml`      |

Follow the [XDG Base Directory spec](https://specifications.freedesktop.org/basedir-spec/latest/):
user config in `$XDG_CONFIG_HOME` (default `~/.config/`), data in `$XDG_DATA_HOME` (default
`~/.local/share/`), cache in `$XDG_CACHE_HOME` (default `~/.cache/`).

## Environment Variables

- Names: UPPERCASE, underscores, no leading digits. Prefix with `MYAPP_`.
- Keep values single-line.
- Don't commandeer standard names (see POSIX list).
- Read from `.env` file where appropriate, but don't use `.env` as a config file substitute.

### Standard Env Vars to Respect

`NO_COLOR`, `FORCE_COLOR`, `DEBUG`, `EDITOR`, `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`,
`SHELL`, `TERM`, `TERMINFO`, `TMPDIR`, `HOME`, `PAGER`, `LINES`, `COLUMNS`.

### Secrets Warning

Do NOT read secrets from env vars. They leak into process lists, logs, `docker inspect`, and
`systemctl show`. Use credential files, pipes, `AF_UNIX` sockets, or a secret manager.

## Naming

1. Simple, memorable word. Not too generic (avoid collisions like `convert`).
2. Lowercase only, dashes if needed. `curl` not `DownloadURL`.
3. Keep it short. Common tools earn 2-3 letter names; yours should be a short word.
4. Easy to type. Avoid awkward hand positions (the `plum` → `fig` lesson).

## Future-Proofing

1. Keep changes additive. Add new flags; don't change existing behavior.
2. Warn before deprecating. Show deprecation notice, suggest the replacement, detect when user has
   migrated and stop warning.
3. Human-facing output can change freely. Encourage `--plain` / `--json` in scripts.
4. No catch-all subcommand (blocks adding new subcommands).
5. No arbitrary abbreviations (blocks adding new commands with same prefix).
6. No time bombs. Will this still work in 20 years without your server?

## Argument Parsing Libraries

| Language | Recommended libraries                                                                                      |
| -------- | ---------------------------------------------------------------------------------------------------------- |
| Python   | [Click](https://click.palletsprojects.com/), [Typer](https://github.com/tiangolo/typer), argparse (stdlib) |
| Go       | [Cobra](https://github.com/spf13/cobra), [urfave/cli](https://github.com/urfave/cli)                       |
| Rust     | [clap](https://docs.rs/clap)                                                                               |
| Node     | [oclif](https://oclif.io/)                                                                                 |
| Deno     | [parseArgs](https://jsr.io/@std/cli/doc/parse-args/~/parseArgs)                                            |
| Java     | [picocli](https://picocli.info/)                                                                           |
| Kotlin   | [clikt](https://ajalt.github.io/clikt/)                                                                    |
| Ruby     | [TTY](https://ttytoolkit.org/)                                                                             |
| Swift    | [swift-argument-parser](https://github.com/apple/swift-argument-parser)                                    |
| Haskell  | [optparse-applicative](https://hackage.haskell.org/package/optparse-applicative)                           |
| PHP      | [symfony/console](https://github.com/symfony/console)                                                      |
| Bash     | [argbash](https://argbash.dev)                                                                             |
| Any      | [docopt](http://docopt.org)                                                                                |
