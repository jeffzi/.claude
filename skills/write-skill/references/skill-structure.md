# SKILL.md Structure and Discovery

## Contents

- [When to create a skill](#when-to-create-a-skill) — create vs. don't-create tests
- [Frontmatter](#frontmatter) — name and description fields
- [Body sections](#body-sections) — adapting structure to content
- [Steps and completion criteria](#steps-and-completion-criteria) — checkable, demanding step bounds
- [Co-location](#co-location) — grouping one concept's material under one heading
- [File organization](#file-organization) — what stays inline vs references
- [Claude Search Optimization (CSO)](#claude-search-optimization-cso) — descriptions, keywords,
  leading words, naming

---

## When to create a skill

**Create when:**

- A technique wasn't intuitively obvious
- The pattern applies broadly across projects
- Others (or future Claude instances) would benefit
- You need to enforce discipline under pressure

**Don't create for:**

- One-off solutions — just do the work
- Standard practices Claude already knows
- Project-specific conventions — put those in CLAUDE.md
- Mechanical constraints — automate with regex, linting, or CI instead
- Facts the environment already answers — `package.json` scripts, `--help` output, directory layout.
  A skill restating them is a cache that goes stale; document only what no lookup reveals (unwritten
  conventions, rationale, gotchas)

## Frontmatter

```yaml
---
name: skill-name-with-hyphens
description: |
  Use when [specific triggering conditions and symptoms].
  Also use when [additional triggers]. [Technology scope if applicable.]
---
```

- `name`: lowercase letters, numbers, hyphens only (max 64 chars) — no parentheses or special
  characters, no reserved words "anthropic"/"claude". Optional in Claude Code (defaults to the
  directory name); required for claude.ai/API uploads.
- `description`: third person, starts with "Use when...", states capability and _triggering
  conditions_ — never the workflow. Front-load the key use case (budget and truncation rules in
  [frontmatter.md](frontmatter.md)).

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

## Steps and completion criteria

For workflow and task skills, every step ends on a **completion criterion** — the condition that
tells the agent the step is done. Two properties make it a lever:

- **Checkable** — the agent can tell done from not-done. A vague bound ("understanding reached")
  invites premature completion: the agent rushes to the visible next step. Sharpen the bound before
  restructuring anything.
- **Demanding** — how much the bound requires. "Every modified file accounted for" forces thorough
  digging where "produce a change list" does not. Demand also binds flat reference: "every rule
  applied" sets an exhaustiveness bar for a checklist the same way "every step done" does for a
  sequence.

## Co-location

Keep everything about one concept — its definition, rules, and caveats — under one heading, so
reading any part brings the rest with it. Scattering fragments one meaning across sections; it is
distinct from duplication, which repeats one meaning in two places. The load-bearing failure: a
caveat filed under Common mistakes that qualifies a command documented in Quick reference is
invisible to the reader who found the command. When writing or reviewing a skill, trace each core
concept through the file — if its material lives in three sections, group it under one.

## File organization

```text
skill-name/
  SKILL.md              # Main reference (required)
  references/           # Heavy reference material (100+ lines each)
    api-reference.md    # API docs, syntax guides
    examples.md         # Extended examples
  scripts/              # Executable tools, validators
```

**Keep inline:** principles, concepts, code patterns under 50 lines, everything small.

**Separate files for:** heavy reference (100+ lines), reusable scripts/tools, extended examples.

**Disclosure test — branching.** Size says when to consider moving content out; branch coverage says
what to move: inline what every use of the skill needs, push into a reference file what only some
paths reach. Reference material that only some runs need buries the steps every run needs.

**One level deep only.** Don't nest references that reference other references — Claude may not
follow the chain.

**Table of contents for long reference files.** Files over 100 lines need a TOC at the top so Claude
understands the available content even with partial reads.

## Claude Search Optimization (CSO)

The description field determines whether Claude loads your skill. Optimize for discovery.

These rules apply to descriptions the model reads. A `disable-model-invocation: true` skill's
description is never shown to the model — write it as a one-line human summary for the `/` menu,
trigger lists stripped.

### Description rules

1. **Start with "Use when..."** — lead with triggering conditions. A clause on _what_ the skill does
   aids selection among many skills; _how_ it works is what invites shortcutting
2. **Include symptoms** — error messages, situations, frustrations that signal this skill applies
3. **Write in third person** — the description is injected into the system prompt
4. **Never summarize the skill's workflow** — Claude may follow the summary instead of reading the
   full skill body
5. **State what the skill is NOT for** — "Not for X — use Y" boundaries prevent false positives and
   route to sibling skills

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

Trigger phrases and example requests can also go in the optional `when_to_use` frontmatter field —
appended to the description in the skill listing.

### Keyword coverage

Use words Claude would search for:

- **Error messages:** "Hook timed out", "ENOTEMPTY", "race condition"
- **Symptoms:** "flaky", "hanging", "zombie", "pollution"
- **Synonyms:** "timeout/hang/freeze", "cleanup/teardown/afterEach"
- **Tools:** actual commands, library names, file types

Each synonym must earn its place: keep it only if a realistic should-trigger query fails without it.
"hang" beside "timeout" survives — users genuinely say both, and one doesn't reliably match the
other. "review/check/inspect" is one trigger written three times — the model matches "check my code"
against "review" unaided. Every dead synonym spends the 1,536-char cap a live trigger needs.

### Leading words

A **leading word** is a compact concept the model already holds from pretraining, repeated as a
single token to anchor behavior: a _tight_ loop instead of "fast, deterministic, low-overhead"; a
_cache_ instead of "a copy of an expensive lookup that can go stale". In the body it makes the agent
reach for the same behavior each time the word appears; in a description it triggers more reliably
when the same word lives in the user's prompts and codebase. Prefer existing words — coined ones
recruit no priors, so you pay in definition what a pretrained word gives free. Hunt for passages
restating one idea across a sentence; each is a candidate to collapse into a single word.

### Naming

**Action skills** (discipline, technique, pattern): verb-first, active voice with hyphens.

- `write-skill` not `skill-writing`
- `condition-based-waiting` not `async-test-helpers`

**Reference skills**: use the domain or tool name directly — `polars`, `fallow`, `scikit-learn`.
Forcing a verb prefix (`use-polars`, `learn-fallow`) hurts discoverability; users search for the
tool name, not an action.
