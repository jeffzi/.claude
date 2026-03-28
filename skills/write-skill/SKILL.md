---
name: write-skill
description: |
  Use when creating new Claude Code skills, editing existing SKILL.md files, or designing skill
  descriptions for discovery. Also use when skills fail to trigger reliably, agents rationalize
  around rules under pressure, or you need to choose between skill types (discipline, technique,
  pattern, reference). For review-only assessment against checklists, use vet-skill. Complements
  skill-creator which handles eval/benchmark infrastructure.
---

# Writing Effective Skills

**Writing skills is TDD applied to process documentation.** Run scenarios without the skill (RED),
write the skill addressing failures (GREEN), close loopholes (REFACTOR).

If you didn't watch an agent fail without the skill, you don't know if the skill prevents the right
failures. This skill covers _design_; use `skill-creator` for eval infrastructure and benchmarking.

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

## The Iron Law

```text
NO SKILL WITHOUT A FAILING TEST FIRST
```

This applies to NEW skills AND EDITS to existing skills.

Write skill before testing? Delete it. Start over. Edit skill without testing? Same violation.

No exceptions — not for "simple additions", "just a section", or "documentation updates." Don't keep
untested changes as "reference."

## Skill types

| Type           | Purpose                      | Testing approach                                            |
| -------------- | ---------------------------- | ----------------------------------------------------------- |
| **Discipline** | Enforce rules under pressure | Pressure scenarios (3+ combined), document rationalizations |
| **Technique**  | Teach a concrete method      | Application to new problems, edge cases                     |
| **Pattern**    | Provide a mental model       | Recognition + counter-examples (when it doesn't apply)      |
| **Reference**  | Document APIs/tools/syntax   | Retrieval scenarios, test common use cases for gaps         |

Discipline skills need persuasion techniques to resist rationalization — read
`references/persuasion-principles.md`.

## SKILL.md structure

Two required frontmatter fields: `name` (letters, numbers, hyphens only) and `description` (starts
with "Use when...", third person, triggering conditions only — never summarize the workflow).

**Body:** Adapt sections to your content — overview, when to use, core pattern, quick reference,
implementation, common mistakes. Not every section applies to every skill type.

**Files:** SKILL.md under 500 lines. Heavy content (100+ lines) in `references/`. One level deep
only — no chains of references referencing references.

Read `references/skill-structure.md` for the full structure template, file organization rules, and
description optimization (CSO).

## Writing for compliance

**Foundational principle:** Violating the letter of the rules is violating the spirit of the rules.
Add this early in any discipline skill. Read `references/persuasion-principles.md` (section "Writing
compliance-resistant rules") for bright-line rules, loophole closing, and rationalization tables.

See `references/persuasion-principles.md` for persuasion alignment by skill type.

## Pressure-testing skills

**The cycle:** RED (run without skill, document failures) → GREEN (write minimal skill, verify
compliance) → REFACTOR (capture new rationalizations, add counters, re-test). Use subagents for
isolation. Read `references/pressure-testing.md` for full methodology.

### Rationalizations for skipping tests

| Excuse                         | Reality                                                    |
| ------------------------------ | ---------------------------------------------------------- |
| "Skill is obviously clear"     | Clear to you ≠ clear to other agents. Test it.             |
| "It's just a reference"        | References can have gaps. Test retrieval.                  |
| "Testing is overkill"          | Untested skills have issues. Always.                       |
| "I'll test if problems emerge" | Problems = agents can't use skill. Test BEFORE deploying.  |
| "Academic review is enough"    | Reading ≠ using. Test application scenarios.               |
| "No time to test"              | Deploying untested skill wastes more time fixing it later. |

## Conciseness

SKILL.md ceiling: 500 lines. Prose under 500 words (excluding code blocks and tables). Move heavy
content to reference files, cross-reference instead of repeating, compress examples (one excellent
beats three mediocre). Match freedom to fragility: prose for flexible tasks, exact scripts for
fragile operations.

## Anti-patterns

| Anti-pattern                    | What to look for                                                  |
| ------------------------------- | ----------------------------------------------------------------- |
| Workflow summary in description | Claude follows summary as shortcut, skips body                    |
| Narrative example               | Session-specific stories instead of general patterns              |
| Multi-language dilution         | Same example in 5+ languages — mediocre quality, maintenance cost |
| Code in flowcharts              | Implementation code in diagrams — can't copy-paste                |
| Generic labels                  | `helper1`, `step3` — labels without semantic meaning              |
| Over-documenting known things   | Standard library usage Claude already knows                       |

## Red flags — STOP and reassess

If any of these are true, you are violating the Iron Law:

- Writing SKILL.md content before running a baseline scenario
- Editing an existing skill without testing the change
- Creating multiple skills in batch without testing each
- Skipping tests because "it's just a reference skill"
- Keeping untested content as "I'll test it later"
- Adding sections based on hypothetical failures, not observed ones

## Deployment checklist

After writing ANY skill, STOP and complete this checklist before moving to the next.

### RED phase — baseline

- [ ] Created test scenarios (pressure for discipline; application for technique; recognition for
      pattern; retrieval for reference)
- [ ] Ran scenarios WITHOUT skill, documented failures and rationalizations verbatim

### GREEN phase — write skill

- [ ] `name` uses only letters, numbers, hyphens
- [ ] `description` starts with "Use when...", third person, no workflow summary
- [ ] SKILL.md under 500 lines; heavy content in reference files
- [ ] Keywords cover errors, symptoms, synonyms, tool names
- [ ] One excellent code example (not multi-language)
- [ ] Common mistakes section included
- [ ] Ran scenarios WITH skill, agent now complies

### For discipline skills (additional)

- [ ] Bright-line rules with absolute language
- [ ] Rationalization table from testing
- [ ] Red flags list
- [ ] Loopholes explicitly closed
- [ ] Persuasion principles matched to skill type

### REFACTOR phase — close loopholes

- [ ] Identified new rationalizations from testing
- [ ] Added explicit counters for each
- [ ] Re-tested — agent still complies
- [ ] Meta-tested to verify clarity

**Use `skill-creator` for:** eval infrastructure, benchmark stats, blind A/B comparison, description
optimization loops, and packaging.

## Attribution

Core principles adapted from
[obra/superpowers/writing-skills](https://github.com/obra/superpowers/tree/main/skills/writing-skills)
by Jesse Vincent, which applies TDD methodology and persuasion research to skill authoring.
