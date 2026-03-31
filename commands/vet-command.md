---
name: vet-command
description: Use when reviewing command .md files for quality, structural, or security issues
argument-hint: "[command file path]"
---

# Command Vet

## Overview

Command `.md` files are pure prose and YAML — no linter catches issues in them. Command vet catches
broken frontmatter, unsafe shell commands, delegation errors, excessive context gathering, unclear
workflows, and security risks that would only surface at runtime.

## Process

1. **Read the command file** in full.
2. **Run through each checklist** below, item by item. Check every item against the file — don't
   batch or skim.
3. **Verify `Skill()` targets** — for every `Skill()` call, confirm the skill exists under `skills/`
   with that exact name.
4. **Verify `!` command safety** — for every `!` line, confirm it's read-only and can't leak
   secrets.
5. **Report findings** using the output format at the bottom.
6. **Apply fixes** directly unless the user asked for review-only.

**Rationalization guard:** Zero issues in a non-trivial command is a re-check signal, not a clean
bill of health. Re-examine shell safety and delegation before concluding.

| Excuse                           | Reality                                                         |
| -------------------------------- | --------------------------------------------------------------- |
| "The `!` commands look fine"     | Did you check each one is read-only? One at a time.             |
| "It's a simple command"          | Simple commands still need correct frontmatter and safe shells. |
| "The `Skill()` call looks right" | Did you verify the skill exists and the name matches exactly?   |
| "No security concerns"           | Did you trace every `!` command for credential exposure?        |

## Checklists

### Frontmatter

- [ ] `description` present and non-empty
- [ ] `description` names concrete use cases, not abstract capabilities
- [ ] `description` does not summarize the command's workflow (Claude follows the summary, skips
      body)
- [ ] `argument-hint` present if the command accepts arguments (body references `$ARGUMENTS` or
      describes expected input)
- [ ] `name` if present uses only lowercase letters, numbers, hyphens, and matches filename

### Shell commands (`!` prefix)

Skip if the command has no `!` lines.

- [ ] Every `!` command is read-only — no writes, deletes, resets, checkouts, or state mutations
- [ ] No `!` command exposes secrets (`cat .env`, `printenv`, credential files)
- [ ] Commands use targeted queries, not bulk dumps (`git log --oneline -10` not `git log --all`)
- [ ] Every `!` command is relevant — no "just in case" context gathering
- [ ] Failure modes considered — what happens if git isn't initialized, file doesn't exist, or
      command returns nothing?

### Skill delegation

Skip if the command neither uses `Skill()` calls nor references skills by name.

- [ ] Every `Skill()` call targets a skill that exists in `skills/` with that exact name
- [ ] References to skills by name (e.g., "load the code-py skill") use `Skill()` syntax — prose
      references risk Claude not actually loading the skill
- [ ] Delegation is appropriate — the skill owns the concern, the command orchestrates
- [ ] No reimplementation of logic the delegated skill already covers
- [ ] Delegation order is correct — load skills before relying on their output

### Workflow clarity

- [ ] Steps numbered and sequenced logically
- [ ] Each step has a single clear action
- [ ] Checkpoints present where order matters ("Verify X before proceeding to Y")
- [ ] Edge cases handled (no changes, missing files, command failures)
- [ ] Output format specified if the command produces structured results

### Security

- [ ] Following the command as written cannot leak credentials into logs, chat, or files
- [ ] Destructive operations (push, delete, reset) require explicit user confirmation
- [ ] External content (URLs, API responses) treated as untrusted if present
- [ ] No `curl | bash` or equivalent patterns

### Structure

- [ ] One coherent concern per command — not two commands jammed together
- [ ] No content Claude already knows (standard git usage, common workflows)
- [ ] Labels are semantic (`step1` bad, `Gather context` good)
- [ ] Concise — no verbose explanations for simple operations
- [ ] Output rules section present if command can be called from other workflows

## Anti-patterns

| Anti-pattern             | What to look for                                                     |
| ------------------------ | -------------------------------------------------------------------- |
| Kitchen-sink context     | 5+ `!` commands gathering everything "just in case"                  |
| Phantom delegation       | `Skill()` call to a nonexistent skill or wrong name                  |
| Prose delegation         | References skills by name without `Skill()` syntax — may not load    |
| Missing delegation       | Reimplementing logic an existing skill already handles               |
| Destructive `!` command  | Shell command that modifies state without user confirmation          |
| Hardcoded paths          | Absolute paths or machine-specific values that won't transfer        |
| Silent failure           | `!` command that fails silently, feeding wrong context to the prompt |
| Workflow summary in desc | Description summarizes steps — Claude follows summary, skips body    |
| Dual-purpose command     | One command doing two unrelated things — split it                    |

## Severity classification

- **Critical** — Command broken or unsafe: missing `description`, `Skill()` to nonexistent skill,
  destructive `!` command without confirmation, credential exposure
- **Important** — Command works but unreliable: excessive context gathering, unclear step ordering,
  missing edge case handling, reimplemented skill logic
- **Minor** — Convention issues: missing `argument-hint`, generic labels, verbose prose, no output
  rules section

## Output format

```markdown
## Command review: [command-name]

**Lines**: [line count]

### Issues

#### Critical (blocks deployment)

- [file:line] **[category]**: Description of issue. Suggested fix.

#### Important (should fix)

- [file:line] **[category]**: Description of issue. Suggested fix.

#### Minor (nice to fix)

- [file:line] **[category]**: Description of issue. Suggested fix.

### Summary

[1-2 sentence overall assessment]
```

Categories: `frontmatter`, `shell-safety`, `delegation`, `workflow`, `security`, `structure`

## Output rules

**When called from preflight or another workflow:** Output NOTHING. Accumulate findings internally
for the caller.

**When called standalone (direct `/vet-command` invocation):**

- Report findings grouped by severity using the format above.
- If everything passes: Just say "No issues found." — nothing else.

**NEVER output:**

- Tables showing all checklist items with "Pass" rows
- Summary of checks that passed
- Progress updates like "Now checking..."
