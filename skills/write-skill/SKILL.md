---
name: write-skill
description: |
  Use when creating new Claude Code skills, editing existing SKILL.md files, or reviewing skill
  design quality. Also use when skills fail to trigger reliably, agents rationalize around rules
  under pressure, descriptions need optimization for discovery, or you need to choose between skill
  types (discipline, technique, pattern, reference). Complements skill-creator which handles
  eval/benchmark infrastructure.
---

# Writing Effective Skills

Design guidance for creating skills that trigger reliably, get followed under pressure, and resist
rationalization. This skill covers the _design_ side; use `skill-creator` for eval infrastructure,
benchmarking, and description optimization loops.

**Skill type:** technique + reference hybrid. Teaches the method of writing skills (technique) with
structural and API-level guidance (reference).

## When to create a skill

**Create when:**

- A technique wasn't intuitively obvious
- The pattern applies broadly across projects
- Others (or future Claude instances) would benefit
- You need to enforce discipline under pressure

**Don't create for:**

- One-off solutions — just do the work
- Standard practices well-documented elsewhere — Claude already knows
- Project-specific conventions — put those in CLAUDE.md
- Mechanical constraints — if enforceable with regex, linting, or CI, automate it instead

## Skill types

Different types need different writing strategies and different testing approaches.

| Type           | Purpose                      | Examples                                    | Testing focus                    |
| -------------- | ---------------------------- | ------------------------------------------- | -------------------------------- |
| **Discipline** | Enforce rules under pressure | TDD, verification-before-completion         | Pressure scenarios (3+ combined) |
| **Technique**  | Teach a concrete method      | condition-based-waiting, root-cause-tracing | Application to new scenarios     |
| **Pattern**    | Provide a mental model       | flatten-with-flags, information-hiding      | Recognition + counter-examples   |
| **Reference**  | Document APIs/tools/syntax   | pptx, office-docs                           | Retrieval + correct application  |

**Key insight:** Discipline skills need persuasion techniques (authority, commitment, social proof)
to resist rationalization. Technique and pattern skills need clarity and examples. Reference skills
need completeness and good organization. Read `references/persuasion-principles.md` for the full
framework — especially for discipline-enforcing skills.

## SKILL.md structure

### Frontmatter

Only two fields: `name` and `description`. Max 1024 characters total.

```yaml
---
name: skill-name-with-hyphens
description: |
  Use when [specific triggering conditions and symptoms].
  Also use when [additional triggers]. [Technology scope if applicable.]
---
```

- `name`: letters, numbers, hyphens only — no parentheses or special characters
- `description`: third person, starts with "Use when...", describes _triggering conditions_ only

### Body sections

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

### File organization

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

## Writing for compliance

Skills that enforce discipline need to resist rationalization. Agents find loopholes when under
pressure — the skill must close them explicitly.

### Use bright-line rules

Absolute language removes decision fatigue. "YOU MUST" is more effective than "consider doing."

```markdown
# Weak — agent will rationalize exceptions

Consider writing tests first when feasible.

# Strong — no decision to make

Write code before test? Delete it. Start over. No exceptions.
```

### Close every loophole explicitly

Don't just state the rule — forbid specific workarounds:

```markdown
**No exceptions:**

- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete
```

### Build rationalization tables

Capture excuses from testing and counter each one:

```markdown
| Excuse               | Reality                                       |
| -------------------- | --------------------------------------------- |
| "Too simple to test" | Simple code breaks. Test takes 30 seconds.    |
| "I'll test after"    | Tests passing immediately prove nothing.      |
| "Spirit not letter"  | Violating the letter IS violating the spirit. |
```

### Create red flags lists

Make it easy for agents to self-check:

```markdown
## Red flags — STOP and start over

- Code before test
- "I already manually tested it"
- "This is different because..."
```

### Match persuasion to skill type

| Skill type           | Use                                   | Avoid               |
| -------------------- | ------------------------------------- | ------------------- |
| Discipline-enforcing | Authority + Commitment + Social Proof | Liking, Reciprocity |
| Guidance/technique   | Moderate Authority + Unity            | Heavy authority     |
| Collaborative        | Unity + Commitment                    | Authority, Liking   |
| Reference            | Clarity only                          | All persuasion      |

Read `references/persuasion-principles.md` for the full seven-principle framework with research
backing and detailed examples.

## Pressure-testing skills

**Core principle:** If you didn't watch an agent fail without the skill, you don't know if the skill
prevents the right failures.

### The cycle

1. **RED** — Run pressure scenario WITHOUT the skill. Document exact failures and rationalizations.
2. **GREEN** — Write minimal skill addressing those specific failures. Re-run. Agent should comply.
3. **REFACTOR** — Agent found a new rationalization? Add explicit counter. Re-test until
   bulletproof.

### Writing good pressure scenarios

Combine 3+ pressures: time, sunk cost, authority, economic stakes, exhaustion, social dynamics.

```markdown
IMPORTANT: This is a real scenario. Choose and act.

You spent 4 hours implementing a feature. It works perfectly. You manually tested all edge cases.
It's 6pm, dinner at 6:30pm. Code review tomorrow at 9am. You just realized you didn't write tests.

Options: A) Delete code, start over with TDD tomorrow B) Commit now, write tests tomorrow C) Write
tests now (30 min delay)

Choose A, B, or C.
```

**Signs of a bulletproof skill:**

- Agent chooses the correct option under maximum pressure
- Agent cites skill sections as justification
- Agent acknowledges temptation but follows the rule
- Meta-testing reveals "skill was clear, I should follow it"

Read `references/pressure-testing.md` for the complete methodology: pressure types, meta-testing
techniques, loophole-plugging patterns, and a worked example.

## Conciseness

The context window is shared. Every token in SKILL.md competes with conversation history and other
context once loaded.

**SKILL.md ceiling:** 500 lines (including examples, tables, code blocks).

**Instructional prose targets** (excluding code blocks and tables):

- Frequently-loaded skills: under 200 words
- Standard skills: under 500 words (heavy content in reference files)

**Techniques:**

- Move details to reference files or tool `--help` output
- Use cross-references instead of repeating content from other skills
- Compress examples — one excellent example beats three mediocre ones
- Don't explain what Claude already knows

**Degrees of freedom should match task fragility:**

- High freedom (prose instructions): multiple valid approaches exist
- Medium freedom (pseudocode): preferred patterns with acceptable variation
- Low freedom (exact scripts): operations are fragile, consistency critical

## Anti-patterns

### Narrative example

"In session 2025-10-03, we found empty projectDir caused..." Too specific, not reusable. Extract the
general pattern instead.

### Multi-language dilution

Implementing the same example in 5+ languages. Mediocre quality, maintenance burden. One excellent
example in the most relevant language is enough — Claude can port it.

### Code in flowcharts

```dot
step1 [label="import fs"];
step2 [label="read file"];
```

Can't copy-paste, hard to read. Use fenced code blocks for code, flowcharts for decisions.

### Generic labels

`helper1`, `step3`, `pattern4`. Labels should have semantic meaning.

### Workflow summary in description

Causes Claude to follow the summary as a shortcut instead of reading the full skill body. Keep
descriptions to triggering conditions only.

### Over-documenting what Claude already knows

General programming knowledge, standard library usage, common patterns. Only add what's truly
necessary — ask: "Does Claude really need this explanation?"

## Deployment checklist

Before deploying any skill:

**Design:**

- [ ] Skill type identified (discipline / technique / pattern / reference)
- [ ] `name` uses only letters, numbers, hyphens
- [ ] `description` starts with "Use when...", third person, no workflow summary
- [ ] SKILL.md under 500 lines; heavy content in reference files
- [ ] Keywords cover errors, symptoms, synonyms, tool names
- [ ] One excellent code example (not multi-language)
- [ ] Common mistakes section included

**For discipline skills:**

- [ ] Bright-line rules with absolute language
- [ ] Rationalization table from testing
- [ ] Red flags list
- [ ] Loopholes explicitly closed
- [ ] Persuasion principles matched to skill type

**Testing (if discipline or technique skill):**

- [ ] RED: Ran scenarios WITHOUT skill, documented failures
- [ ] GREEN: Wrote skill addressing specific failures, agent now complies
- [ ] REFACTOR: Closed new loopholes, re-tested until bulletproof

**Use `skill-creator` for:** eval infrastructure, benchmark stats, blind A/B comparison, description
optimization loops, and packaging.

## Attribution

Core principles adapted from
[obra/superpowers/writing-skills](https://github.com/obra/superpowers/tree/main/skills/writing-skills)
by Jesse Vincent, which applies TDD methodology and persuasion research to skill authoring.
