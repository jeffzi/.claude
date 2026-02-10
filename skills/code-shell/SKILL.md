---
name: code-shell
description: >
  Use when writing Bash/shell scripts, encountering "unbound variable" or
  "command not found" errors, or scripts failing silently. Apply for
  automation, hooks, CI/CD, CLI tools, or any .sh files.
---

# Shell Scripting - Bash Best Practices

## Overview

Write safe, portable, maintainable shell scripts using strict mode, proper quoting, and modern Bash
features. Based on [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
with safety patterns from
[SixArm Unix Shell Tactics](https://github.com/SixArm/unix-shell-script-tactics).

**Core principle:** Every script uses strict mode. Quick scripts become production scripts—write
them correctly the first time.

## When to Use

Use for ALL shell scripts, including:

- "Quick" automation scripts
- Git hooks and CI/CD scripts
- CLI wrapper tools
- Any `.sh` file

Don't skip because code seems simple, "just a one-liner", or "I'll fix it later".

## Quick Reference

| Task                 | Pattern                                  |
| -------------------- | ---------------------------------------- |
| Shebang              | `#!/usr/bin/env bash`                    |
| Strict mode          | `set -euo pipefail`                      |
| Check dependency     | `command -v tool >/dev/null \|\| exit 1` |
| Quote variables      | `"$var"` not `$var`                      |
| Command substitution | `$(cmd)` not backticks                   |
| Test syntax          | `[[ ]]` not `[ ]`                        |
| Output               | `printf "%s\n" "$msg"` not `echo`        |
| Cleanup on exit      | `trap cleanup EXIT`                      |
| Source file          | `. file` not `source file`               |

## Formatting

Use `shfmt` defaults:

- **Indentation:** Tabs
- **Binary ops:** At start of line for continuation
- **Switch cases:** Indented
- **Redirects:** Following command
- **Simplify:** Enabled

## Mandatory Rules

### Shebang

**Always use portable shebang:**

```bash
#!/usr/bin/env bash
```

Not `#!/bin/bash` (path varies across systems).

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

### Quote All Variables

**Always quote variables to prevent word splitting:**

```bash
# ✗ NEVER
echo $var
rm $file

# ✓ ALWAYS
echo "$var"
rm "$file"
```

**Exception:** Inside `[[ ]]` where word splitting doesn't occur (but quote anyway for consistency).

### Use printf Over echo

**Prefer `printf` for reliable output:**

```bash
# ✗ Unreliable with special characters
echo "Value: $value"
echo -e "Line1\nLine2"

# ✓ Portable and predictable
printf "Value: %s\n" "$value"
printf "Line1\nLine2\n"
```

### Modern Test Syntax

**Use `[[ ]]` not `[ ]`:**

```bash
# ✗ Old syntax, quirky behavior
if [ -z "$var" ]; then
if [ "$a" = "$b" ]; then

# ✓ Modern, safer
if [[ -z "$var" ]]; then
if [[ "$a" == "$b" ]]; then
```

### Command Substitution

**Use `$()` not backticks:**

```bash
# ✗ Hard to read, can't nest
files=`ls`

# ✓ Clear, nestable
files=$(ls)
nested=$(echo $(date))
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

| ✗ Never                       | ✓ Always                           |
| ----------------------------- | ---------------------------------- |
| `#!/bin/bash`                 | `#!/usr/bin/env bash`              |
| No `set -euo pipefail`        | Strict mode at top of every script |
| `echo` with escapes/variables | `printf` for reliable output       |
| `[ ]` for tests               | `[[ ]]`                            |
| Unquoted `$var`               | `"$var"`                           |
| Backticks `` `cmd` ``         | `$(cmd)`                           |
| `source file`                 | `. file` (POSIX)                   |
| `cd dir && ...`               | `cd dir \|\| exit 1`               |
| No cleanup on exit            | `trap cleanup EXIT`                |
| `==` in `[ ]`                 | `=` in `[ ]` or `==` in `[[ ]]`    |
| `$?` after pipe               | `${PIPESTATUS[@]}`                 |
| `for f in $(ls)`              | `for f in ./*`                     |
| Cat useless use               | `< file command`                   |

## Common Patterns

```bash
# Iterate files (handles spaces in names)
for file in ./*.sh; do
 [[ -e "$file" ]] || continue  # Handle empty glob
 process "$file"
done

# Read lines from file
while IFS= read -r line; do
 printf "%s\n" "$line"
done < "$input_file"

# Exit with error message
die() {
 printf "Error: %s\n" "$1" >&2
 exit "${2:-1}"
}
```

## Rationalizations That Mean You're About to Fail

| Excuse                          | Reality                                           |
| ------------------------------- | ------------------------------------------------- |
| "Just a quick script"           | Quick scripts become production. Use strict mode. |
| "It works on my machine"        | Use `#!/usr/bin/env bash` for portability.        |
| "I'll add error handling later" | You won't. Add `set -euo pipefail` now.           |
| "Quoting is ugly"               | Unquoted variables cause bugs. Quote everything.  |
| "echo is simpler"               | `printf` is reliable. `echo` behavior varies.     |

## Verification

**MANDATORY before completing any task:**

```bash
shfmt -d .           # Check formatting (add -w to fix)
shellcheck *.sh      # Lint for issues
```

**Task is NOT complete until both pass.**

Key ShellCheck codes: SC2086 (quote expansion), SC2046 (quote command sub), SC2006 (use $()), SC2004
(unnecessary $), SC2034 (unused variable).

## Related Commands

- `/vet` - Vet shell scripts against these rules
