# SKILL.md Structure and Discovery

## Contents

- [Frontmatter](#frontmatter) — name and description fields
- [Body sections](#body-sections) — adapting structure to content
- [File organization](#file-organization) — what stays inline vs references
- [Claude Search Optimization (CSO)](#claude-search-optimization-cso) — descriptions, keywords,
  naming

---

## Frontmatter

The two most important fields are `name` and `description`. Get these right first.

```yaml
---
name: skill-name-with-hyphens
description: |
  Use when [specific triggering conditions and symptoms].
  Also use when [additional triggers]. [Technology scope if applicable.]
---
```

- `name`: letters, numbers, hyphens only — no parentheses or special characters
- `description`: third person, starts with "Use when...", describes _triggering conditions_ only.
  Front-load the key use case — descriptions are truncated at 250 chars per entry in the skill
  listing.

**11 additional optional fields** control invocation, tool access, model selection, subagent
execution, auto-activation paths, and dynamic context injection. See
[frontmatter.md](frontmatter.md) for the full reference.

## Body sections

Adapt this structure to fit your content — not every section applies to every skill type. The order
and naming should serve clarity, not match this template rigidly.

```markdown
# Skill Name

## Overview

What is this? Core principle in 1-2 sentences.

## When to use

Bullet list with symptoms and use cases. When NOT to use. Related skills to use instead. [Small
inline flowchart IF decision is non-obvious]

## Core pattern (for techniques/patterns)

Before/after comparison. One excellent example beats many mediocre ones.

## Quick reference

Table or bullets for scanning common operations.

## Implementation

Inline code for simple patterns. Link to reference file for heavy content.

## Common mistakes

What goes wrong + fixes. For discipline skills: rationalization table.
```

## File organization

```text
skill-name/
  SKILL.md              # Main reference (required, under 500 lines)
  references/           # Heavy reference material (100+ lines each)
    api-reference.md    # API docs, syntax guides
    examples.md         # Extended examples
  scripts/              # Executable tools, validators
```

**Keep inline:** principles, concepts, code patterns under 50 lines, everything small.

**Separate files for:** heavy reference (100+ lines), reusable scripts/tools, extended examples.

**One level deep only.** Don't nest references that reference other references — Claude may not
follow the chain.

**Table of contents for long reference files.** Files over 100 lines need a TOC at the top so Claude
understands the available content even with partial reads.

## Claude Search Optimization (CSO)

The description field determines whether Claude loads your skill. Optimize for discovery.

### Description rules

1. **Start with "Use when..."** — focus on triggering conditions, not what the skill does
2. **Include symptoms** — error messages, situations, frustrations that signal this skill applies
3. **Write in third person** — the description is injected into the system prompt
4. **Never summarize the skill's workflow** — Claude may follow the summary instead of reading the
   full skill body

```yaml
# BAD: Summarizes workflow — Claude may follow this instead of reading the skill
description: Use when executing plans — dispatches subagent per task with code review between tasks

# BAD: Too abstract
description: For async testing

# GOOD: Triggering conditions only, no workflow summary
description: Use when executing implementation plans with independent tasks in the current session

# GOOD: Includes symptoms
description: |
  Use when tests have race conditions, timing dependencies, or pass/fail inconsistently.
  Also use when tests use polling loops or sleep-based waits.
```

**Why no workflow in descriptions:** Testing revealed that when a description summarizes the skill's
workflow, Claude may follow the description as a shortcut instead of reading the full skill. A
description saying "code review between tasks" caused Claude to do ONE review, even though the
skill's body specified TWO reviews. Removing the workflow summary from the description fixed this.

### Keyword coverage

Use words Claude would search for:

- **Error messages:** "Hook timed out", "ENOTEMPTY", "race condition"
- **Symptoms:** "flaky", "hanging", "zombie", "pollution"
- **Synonyms:** "timeout/hang/freeze", "cleanup/teardown/afterEach"
- **Tools:** actual commands, library names, file types

### Naming

Use verb-first, active voice with hyphens:

- `write-skill` not `skill-writing`
- `condition-based-waiting` not `async-test-helpers`

Gerunds work well for processes: `creating-skills`, `testing-skills`.
