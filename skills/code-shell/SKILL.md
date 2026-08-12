---
name: code-shell
description: >
  Use when writing Bash/shell scripts, encountering "unbound variable" or
  "command not found" errors, or scripts failing silently. Apply for
  automation, hooks, CI/CD, CLI tools, or any .sh files. Not for fish, zsh,
  or PowerShell — Bash/sh only. Applies to *.sh and *.bash files.
user-invocable: false
---

# Shell Scripting - Bash Best Practices

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

## Overview

Write safe, portable, maintainable shell scripts using strict mode, proper quoting, and modern Bash
features. Based on [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
with safety patterns from
[SixArm Unix Shell Tactics](https://github.com/SixArm/unix-shell-script-tactics).

**Core principle:** Every script uses strict mode.

## Formatting

Use `shfmt` defaults:

- **Indentation:** Tabs
- **Binary ops:** At start of line for continuation
- **Switch cases:** Indented
- **Redirects:** Following command
- **Simplify:** Enabled

Do not copy the indentation of this file's code blocks — a markdown formatter re-indents them. Write
scripts with tabs, or run `shfmt -w` after writing.

## Mandatory Rules

### Strict Mode

**Every script starts with strict mode:**

```bash
set -euo pipefail
```

| Flag          | Effect                              |
| ------------- | ----------------------------------- |
| `-e`          | Exit on error                       |
| `-u`          | Error on undefined variables        |
| `-o pipefail` | Pipeline fails if any command fails |

### Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# Check dependencies
command -v jq >/dev/null || {
 printf "Error: jq is required\n" >&2
 exit 1
}

main() {
 local arg="${1:-}"
 # script logic here
}

main "$@"
```

### Trap for Cleanup

**Use trap for cleanup on exit:**

```bash
cleanup() {
 rm -f "$temp_file"
}
trap cleanup EXIT

temp_file=$(mktemp)
# script continues...
```

## Naming Conventions

| Element             | Convention   | Example                  |
| ------------------- | ------------ | ------------------------ |
| Variables           | `snake_case` | `local file_path`        |
| Constants           | `UPPER_CASE` | `readonly MAX_RETRIES=3` |
| Functions           | `snake_case` | `process_file()`         |
| Environment exports | `UPPER_CASE` | `export API_KEY`         |

## Pitfalls

| ✗ Never                                | ✓ Always                                  |
| -------------------------------------- | ----------------------------------------- |
| `#!/bin/bash` (path varies)            | `#!/usr/bin/env bash`                     |
| No `set -euo pipefail`                 | Strict mode at top of every script        |
| `echo` with escapes/variables          | `printf "%s\n" "$var"`                    |
| `[ ]` for tests                        | `[[ ]]`                                   |
| Unquoted `$var`                        | `"$var"`                                  |
| Backticks `` `cmd` ``                  | `$(cmd)`                                  |
| `. lib.sh` (bare name searches `PATH`) | `. ./lib.sh`                              |
| `cd dir` unchecked                     | `cd dir \|\| exit 1` (or `cd dir && cmd`) |
| No cleanup on exit                     | `trap cleanup EXIT`                       |
| `==` in `[ ]`                          | `=` in `[ ]` or `==` in `[[ ]]`           |
| `$?` after pipe                        | `${PIPESTATUS[@]}`                        |
| `for f in $(ls)`                       | `for f in ./*`                            |
| `cat file \| grep x`                   | `grep x < file`                           |

## Common Patterns

```bash
# Iterate files (handles spaces in names)
for file in ./*.sh; do
 [[ -e "$file" ]] || continue # Handle empty glob
 process "$file"
done

# Read lines from file
while IFS= read -r line; do
 printf "%s\n" "$line"
done <"$input_file"

# Exit with error message
die() {
 printf "Error: %s\n" "$1" >&2
 exit "${2:-1}"
}
```

## Rationalizations That Mean You're About to Fail

| Excuse                          | Reality                                          |
| ------------------------------- | ------------------------------------------------ |
| "It works on my machine"        | Use `#!/usr/bin/env bash` for portability.       |
| "I'll add error handling later" | You won't. Add `set -euo pipefail` now.          |
| "Quoting is ugly"               | Unquoted variables cause bugs. Quote everything. |
| "echo is simpler"               | `printf` is reliable. `echo` behavior varies.    |

## Verification

**MANDATORY before completing any task:**

```bash
shfmt -d .                  # Check formatting (add -w to fix)
shellcheck $(shfmt -f .)    # Lint every shell file shfmt finds, recursively
```

**Task is NOT complete until both pass.**

Key ShellCheck codes: SC2086 (quote expansion), SC2046 (quote command sub), SC2006 (use $()), SC2004
(unnecessary $), SC2034 (unused variable).
