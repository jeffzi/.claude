---
name: write-skill
description: |
  Use when creating Claude Code skills, editing SKILL.md files, designing skill descriptions, or
  choosing between skill types (discipline, technique, pattern, reference). Also
  when skills fail to trigger reliably or agents rationalize around rules under pressure. To
  review an existing skill and fix what the review finds, use /revise-skill.
argument-hint: "[skill name or purpose]"
---

# Writing Effective Skills

## Development loop

1. **Capture intent** — enablement, triggers, expected output written down.
2. **Run failing scenarios without the skill** (RED) — every failure and rationalization recorded
   verbatim. This is the Iron Law.
3. **Draft the skill** (GREEN) — every recorded failure has a counter.
4. **Pressure-test** — close loopholes (REFACTOR) until re-runs comply:
   `references/pressure-testing.md`.
5. **Validate triggers** per its trigger-validation section — every should/should-not query scores
   correctly.

## The Iron Law

```text
NO SKILL WITHOUT A FAILING TEST FIRST
```

Write skill before testing? Delete it. Start over. Edit skill without testing? Same violation.

**Foundational principle:** Violating the letter of the rules is violating the spirit of the rules.

No exceptions — not for "simple additions", "just a section", or "documentation updates." Don't keep
untested changes as "reference."

### Rationalizations for skipping tests

| Excuse                         | Reality                                                    |
| ------------------------------ | ---------------------------------------------------------- |
| "Skill is obviously clear"     | Clear to you ≠ clear to other agents. Test it.             |
| "It's just a reference"        | References can have gaps. Test retrieval.                  |
| "Testing is overkill"          | Untested skills have issues. Always.                       |
| "I'll test if problems emerge" | Problems = agents can't use skill. Test BEFORE deploying.  |
| "Academic review is enough"    | Reading ≠ using. Test application scenarios.               |
| "No time to test"              | Deploying untested skill wastes more time fixing it later. |

## Skill types

| Type           | Purpose                      | Testing approach                                            |
| -------------- | ---------------------------- | ----------------------------------------------------------- |
| **Discipline** | Enforce rules under pressure | Pressure scenarios (3+ combined), document rationalizations |
| **Technique**  | Teach a concrete method      | Application to new problems, edge cases                     |
| **Pattern**    | Provide a mental model       | Recognition + counter-examples (when it doesn't apply)      |
| **Reference**  | Document APIs/tools/syntax   | Retrieval scenarios, test common use cases for gaps         |

## Structure and frontmatter

`references/skill-structure.md` covers skill-creation criteria, naming and description rules, the
body template, file organization, CSO, and workflow-step completion criteria.

Optional fields (details: `references/frontmatter.md`):

| Field                            | Use for                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------- |
| `argument-hint`                  | Any skill that takes arguments (autocomplete hint)                                                |
| `when_to_use`                    | Extra trigger phrases appended to the description in the listing                                  |
| `disable-model-invocation: true` | Side-effecting workflows (`/deploy`, `/upgrade-*`)                                                |
| `user-invocable: false`          | Reference-only knowledge (`/code-py` isn't an action)                                             |
| `allowed-tools`                  | Read-only skills, tool-scoped skills (`Bash(git *)`)                                              |
| `model`                          | Slash-invoked skills only, and only with a stated reason — see `references/frontmatter.md`        |
| `effort`                         | Slash-invoked skills only, and only with a stated reason — see `references/frontmatter.md`        |
| `paths`                          | Auto-activate on matching files — trades away `Skill()` dispatch; never on a skill loaded by name |
| `context: fork` + `agent`        | Long-running research/exploration tasks                                                           |
| Shell injection (body syntax)    | Pre-inject git status, diffs, outdated lists, etc.                                                |

## Writing for compliance

Discipline skills need persuasion counters: `references/persuasion-principles.md` § "Writing
compliance-resistant rules" — bright lines, loophole closing, rationalization tables, prohibition
zoning.

## Conciseness

SKILL.md ceiling: 500 lines; prose under 500 words (excluding code blocks and tables). Move heavy
content to reference files; cross-reference, don't repeat. Loaded content stays in context all
session — standing instructions only.

Hunt no-ops — a sentence that doesn't change behavior versus the default is deleted whole, settled
by running, not debate.

A **contract skill** — `user-invocable: false`, loaded only by subagents as their operating contract
— is bounded by the no-op test above instead of the word count: every sentence must change behavior
and trace to a documented failure (RED transcript, review finding). Two bounds survive the
exemption: the 500-line ceiling, and duplicate-hunting — restatement is still cut. Do not relocate a
contract's enforcement text to reference files: enforcement text the agent may never read is not in
context when pressure hits. "Agents depend on it" does not qualify a main-session skill; a hub the
main session also loads (`code-core`) stays disqualified no matter how many subagents load it — the
marker is the frontmatter flag plus subagent-only loading.

## Anti-patterns

| Anti-pattern            | What to look for                                                    |
| ----------------------- | ------------------------------------------------------------------- |
| Narrative example       | Session-specific stories instead of general patterns                |
| Multi-language dilution | Same example in 5+ languages — mediocre quality, maintenance cost   |
| Code in flowcharts      | Implementation code in diagrams — can't copy-paste                  |
| Generic labels          | `helper1`, `step3` — labels without semantic meaning                |
| Scattered concept       | One concept's definition, rules, and caveats spread across sections |

## Red flags

Any of these is an Iron Law violation:

- Writing SKILL.md content before running a baseline scenario
- Editing an existing skill without testing the change
- Creating multiple skills in batch without testing each
- Skipping tests because "it's just a reference skill"
- Keeping untested content as "I'll test it later"
- Adding sections based on hypothetical failures, not observed ones

## Deployment checklist

Run both checklists in `references/pressure-testing.md` — testing and deployment — before deploying.
