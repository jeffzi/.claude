---
name: write-skill
description: |
  Use when creating new Claude Code skills, editing existing SKILL.md files, or designing skill
  descriptions for discovery. Also use when skills fail to trigger reliably, agents rationalize
  around rules under pressure, or you need to choose between skill types (discipline, technique,
  pattern, reference). To review an existing skill against the checklists and fix what it finds,
  use /revise-skill.
argument-hint: "[skill name or purpose]"
---

# Writing Effective Skills

**Writing skills is TDD applied to process documentation.** Run scenarios without the skill (RED),
write the skill addressing failures (GREEN), close loopholes (REFACTOR).

If you didn't watch an agent fail without the skill, you don't know if the skill prevents the right
failures.

## Development loop

1. **Capture intent.** What should the skill enable? When should it trigger (user phrases,
   symptoms)? What's the expected output? Write these down before drafting — unclear intent produces
   unfocused skills.
2. **Run failing scenarios without the skill** (RED). This is the Iron Law.
3. **Draft the skill** addressing those failures (GREEN).
4. **Pressure-test** — rerun under pressure, document rationalizations, close loopholes (REFACTOR).
   See `references/pressure-testing.md`.
5. **Validate triggers** — verify the description activates on should-trigger queries and ignores
   should-not-trigger queries. See the trigger-validation section in `pressure-testing.md`.
6. **Generalize, don't overfit.** When fixing failures, make the rule cover the whole category —
   don't encode your exact test queries verbatim. The skill fails the next unseen paraphrase if you
   do.

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

**Foundational principle:** Violating the letter of the rules is violating the spirit of the rules.

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

## Frontmatter beyond name/description

11 additional optional fields control invocation, tool access, model selection, subagent execution,
and dynamic context injection. Match each to the skill's role:

| Field                            | Use for                                                              |
| -------------------------------- | -------------------------------------------------------------------- |
| `argument-hint`                  | Any skill that takes arguments (autocomplete hint)                   |
| `disable-model-invocation: true` | Side-effecting workflows (`/deploy`, `/upgrade-*`)                   |
| `user-invocable: false`          | Reference-only knowledge (`/code-py` isn't an action)                |
| `allowed-tools`                  | Read-only skills, tool-scoped skills (`Bash(git *)`)                 |
| `model`                          | Slash-invoked skills only, and only with a stated reason — see below |
| `effort`                         | Slash-invoked skills only, and only with a stated reason — see below |
| `paths`                          | Auto-activate when editing matching file types                       |
| `context: fork` + `agent`        | Long-running research/exploration tasks                              |
| Shell injection (body syntax)    | Pre-inject git status, diffs, outdated lists, etc.                   |

Read `references/frontmatter.md` for the complete reference, `allowed-tools` syntax, string
substitutions (`$ARGUMENTS`, `${CLAUDE_SKILL_DIR}`), subagent execution details, and the description
truncation/budget rules.

### `model` and `effort` are slash-path only

Both fields take effect only when the user types `/skill-name`. Loaded through the `Skill()` tool,
or reached inside a subagent, both are **inert** — the surrounding turn's model and effort govern.

This matters twice over:

- **A load-only skill should declare neither.** `code-core`, `test-core`, and the language leaves
  are reached through `Skill()`, so a `model:` line there changes nothing and tells the next reader
  something false.
- **A live declaration overrides the user's `/model` choice for the whole turn.** That needs a
  stated reason — a genuine quality floor for the workflow, not "this skill feels important".
  Liveness alone is not a reason.

`disable-model-invocation: true` settles the question in one direction: slash is the only path, so
the declaration is always live and always needs its reason.

The upstream docs say both fields apply "when this skill is active", with no invocation-path
qualifier — do not take that as license to declare them on load-only skills.
`references/frontmatter.md` has the criterion table and the per-path verification method.

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
- [ ] `model`/`effort` declared only if the skill is slash-invoked, and each has a stated reason;
      otherwise both omitted (see `references/frontmatter.md`)
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

## Attribution

Core principles adapted from
[obra/superpowers/writing-skills](https://github.com/obra/superpowers/tree/main/skills/writing-skills)
by Jesse Vincent, which applies TDD methodology and persuasion research to skill authoring.
