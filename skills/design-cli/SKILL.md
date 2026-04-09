---
name: design-cli
description: >-
  Use when designing a new CLI tool, reviewing an existing CLI interface,
  adding subcommands or flags, writing help text, structuring output for
  humans and machines, or handling errors and configuration in command-line
  programs. Not for GUI or TUI design.
model: sonnet
effort: medium
---

# CLI Interface Design

## Overview

Design for humans first, but never break machines. Decision framework and review checklist for CLI
programs, distilled from [clig.dev](https://clig.dev).

## When to Use

- Designing a new CLI tool or adding subcommands/flags
- Reviewing an existing CLI interface for usability and safety
- Writing help text or error messages
- Structuring output for both humans and scripts
- Choosing between flags, args, env vars, and config files

## When NOT to Use

- Library/API design (different conventions apply)
- GUIs or TUIs with interactive frameworks (e.g. textual, blessed)

## First Question

If the primary audience isn't clear from context, use AskUserQuestion to ask:

- **Question:** "Who is the primary audience for this CLI?"
- **Options:**
  - **Humans** — interactive use, colorized output, friendly errors
  - **Machines** — structured JSON, minimal noise, strict exit codes
  - **Both** — detect TTY and switch between human/machine modes

This shapes every downstream decision (output format, error style, flag design).

## Core Principles

| Principle      | Implication                                                  |
| -------------- | ------------------------------------------------------------ |
| Human-first    | Optimize for interactive use; use TTY detection for machines |
| Composable     | stdout for data, stderr for messages, clean exit codes       |
| Consistent     | Follow conventions and standard flag names                   |
| Right amount   | No silent hangs, no wall of debug output                     |
| Discoverable   | Comprehensive help, examples, suggested next commands        |
| Conversational | Suggest corrections, confirm dangerous actions               |
| Robust         | Validate early, show progress, crash-only design             |

## CLI Design Review Checklist

Walk every category. For each item, mark PASS, FAIL, or N/A. Do not skip items because they "seem
obvious." Score each category (pass/total applicable).

### Help and Discoverability

- [ ] `-h`/`--help` shows full help; no-args shows concise help with examples
- [ ] Help leads with examples, not flag lists
- [ ] Typo suggestions and per-subcommand help
- [ ] Each subcommand has its own `--help`
- [ ] Help links to web docs

### Arguments and Flags

- [ ] Prefer flags over positional args for clarity
- [ ] Every flag has a `--long-form`; short forms only for common flags
- [ ] Standard flag names used (see references/clig-reference.md)
- [ ] Flags and args are order-independent
- [ ] Secrets via `--password-file` or stdin, never `--password`
- [ ] `-` supported for stdin/stdout where files expected

### Output

- [ ] stdout=data, stderr=messages; TTY detection for formatting
- [ ] TTY detection: human-friendly when interactive, machine-friendly when piped
- [ ] Color respects `NO_COLOR`, `TERM=dumb`, `--no-color`
- [ ] `--json` for machines, `--plain` for grep
- [ ] State changes reported to user ("Created X", "Deleted Y")
- [ ] No animations/spinners when stdout is not a TTY

### Errors

- [ ] All errors to stderr, never stdout, with human-readable messages and suggested fixes
- [ ] Most important information printed last (eye drawn to bottom)
- [ ] Stack traces hidden by default, shown with `--verbose` / `-d`
- [ ] Bug report path provided (URL or "run `cmd --bug-report`")

### Interactivity and Safety

- [ ] Prompts only when stdin is TTY; `--no-input` disables all prompts
- [ ] Dangerous operations require confirmation (or `--force`)
- [ ] Ctrl-C exits immediately; second Ctrl-C skips cleanup

### Robustness

- [ ] First output <100ms; progress indicators for ops >1s
- [ ] Network timeouts configurable with sensible defaults
- [ ] Operations are idempotent or recoverable (crash-only design)
- [ ] Input validated early with clear errors

### Configuration

- [ ] Precedence: flags > env vars > project config > user config > system config
- [ ] XDG Base Directory spec for user config (`~/.config/appname/`)
- [ ] Standard env vars respected (`NO_COLOR`, `EDITOR`, `PAGER`, `HTTP_PROXY`, etc.)

### Subcommands

- [ ] Consistent verb naming across object types (`create`, `delete`, not `create`/`remove`)
- [ ] No ambiguous or similarly-named commands (`update` vs `upgrade`)
- [ ] No catch-all subcommand; no arbitrary abbreviations

### Future-Proofing

- [ ] Changes are additive (new flags, not changed behavior)
- [ ] `--version` present
- [ ] No external dependencies that become time bombs

## Common Mistakes

| Mistake                         | Fix                             |
| ------------------------------- | ------------------------------- |
| `--password` flag               | `--password-file` or stdin      |
| Hang silently waiting for stdin | Show help when TTY and no input |
| Catch-all subcommand            | Require explicit subcommand     |

## Deep Reference

See `references/clig-reference.md` for standard flag names, color rules, exit codes, config
precedence, argument parsing libraries, and concrete good/bad examples.
