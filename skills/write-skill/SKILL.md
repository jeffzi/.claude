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

## Development loop

1. **Capture intent.** What should the skill enable? When should it trigger (user phrases,
   symptoms)? What's the expected output? Write these down before drafting — unclear intent produces
   unfocused skills.
2. **Run failing scenarios without the skill** (RED). This is the Iron Law.
3. **Draft the skill** addressing those failures (GREEN).
4. **Pressure-test** — rerun under pressure, document rationalizations, close loopholes (REFACTOR).
   See `references/pressure-testing.md`.
5. **Validate triggers, and generalize, don't overfit** — verify the description activates on
   should-trigger queries and ignores should-not-trigger queries. See the trigger-validation section
   in `pressure-testing.md`.

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

## The Iron Law

```text
NO SKILL WITHOUT A FAILING TEST FIRST
```

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

Read `references/skill-structure.md` for the frontmatter naming and description rules, the structure
template, file organization, and description optimization (CSO).

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

## Frontmatter beyond name/description

Match each optional field to the skill's role:

| Field                            | Use for                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------ |
| `argument-hint`                  | Any skill that takes arguments (autocomplete hint)                                         |
| `when_to_use`                    | Extra trigger phrases appended to the description in the listing                           |
| `disable-model-invocation: true` | Side-effecting workflows (`/deploy`, `/upgrade-*`)                                         |
| `user-invocable: false`          | Reference-only knowledge (`/code-py` isn't an action)                                      |
| `allowed-tools`                  | Read-only skills, tool-scoped skills (`Bash(git *)`)                                       |
| `model`                          | Slash-invoked skills only, and only with a stated reason — see `references/frontmatter.md` |
| `effort`                         | Slash-invoked skills only, and only with a stated reason — see `references/frontmatter.md` |
| `paths`                          | Auto-activate when editing matching file types                                             |
| `context: fork` + `agent`        | Long-running research/exploration tasks                                                    |
| Shell injection (body syntax)    | Pre-inject git status, diffs, outdated lists, etc.                                         |

Read `references/frontmatter.md` for the complete reference, `allowed-tools` syntax, string
substitutions (`\$ARGUMENTS`, `CLAUDE_SKILL_DIR` — literal mentions in a SKILL.md body substitute at
invocation; escape `\$ARGUMENTS` with a backslash), subagent execution details, portability limits
outside Claude Code, and the description truncation/budget rules.

## Writing for compliance

Read `references/persuasion-principles.md` (section "Writing compliance-resistant rules") for
bright-line rules, loophole closing, rationalization tables, and the
steer-positive/adjudicate-negative zoning rule for prohibitions.

## Pressure-testing skills

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

Once invoked, skill content stays in context for the rest of the session — every line is a recurring
token cost. Write standing instructions that apply throughout a task, not one-time steps; the file
is not re-read on later turns.

Hunt no-ops sentence by sentence: an instruction the model already obeys by default pays tokens to
say nothing. The test — does this sentence change behavior versus the default? — is settled by
running the skill, not by debate. When a sentence fails, delete the whole sentence rather than
trimming words from it.

## Anti-patterns

| Anti-pattern            | What to look for                                                    |
| ----------------------- | ------------------------------------------------------------------- |
| Narrative example       | Session-specific stories instead of general patterns                |
| Multi-language dilution | Same example in 5+ languages — mediocre quality, maintenance cost   |
| Code in flowcharts      | Implementation code in diagrams — can't copy-paste                  |
| Generic labels          | `helper1`, `step3` — labels without semantic meaning                |
| Scattered concept       | One concept's definition, rules, and caveats spread across sections |

## Red flags — STOP and reassess

If any of these are true, you are violating the Iron Law:

- Writing SKILL.md content before running a baseline scenario
- Editing an existing skill without testing the change
- Creating multiple skills in batch without testing each
- Skipping tests because "it's just a reference skill"
- Keeping untested content as "I'll test it later"
- Adding sections based on hypothetical failures, not observed ones

## Deployment checklist

Test items (RED/GREEN/REFACTOR runs): use the testing checklist in `references/pressure-testing.md`.

### GREEN phase — write skill

- [ ] Frontmatter and description meet the rules in `references/skill-structure.md` (naming, CSO,
      keyword coverage, sibling boundaries)
- [ ] Frontmatter fields match the role table above (see `references/frontmatter.md`)
- [ ] Common mistakes section included
- [ ] Consistent terminology throughout (one term per concept)
- [ ] No time-sensitive information ("before/after some date, do X")

### For discipline skills (additional)

- [ ] Every structure in `references/persuasion-principles.md` § "Writing compliance-resistant
      rules" present: bright lines, rationalization table from testing, red flags, loophole closure,
      matched persuasion principles
