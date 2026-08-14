# Pressure-Testing Skills

## Contents

- [When to test](#when-to-test)
- [TDD mapping](#tdd-mapping)
- [RED phase: baseline testing](#red-phase-baseline-testing) — writing pressure scenarios, pressure
  types
- [GREEN phase: write minimal skill](#green-phase-write-minimal-skill)
- [REFACTOR phase: close loopholes](#refactor-phase-close-loopholes) — plugging each hole
- [Meta-testing](#meta-testing)
- [Signs of a bulletproof skill](#signs-of-a-bulletproof-skill)
- [Trigger validation](#trigger-validation) — verify description activates on the right prompts
- [Tooling: automate the loop with skill-creator](#tooling-automate-the-loop-with-skill-creator)
- [Testing checklist](#testing-checklist)
- [Deployment checklist](#deployment-checklist) — GREEN-phase writing quality, discipline extras

---

How to verify skills work under pressure using TDD methodology. Pressure scenarios apply to
discipline-enforcing and technique skills; reference skills still get retrieval testing and trigger
validation — the Iron Law applies to every skill.

## When to test

Test skills that:

- Enforce discipline (TDD, testing requirements, verification steps)
- Have compliance costs (time, effort, rework)
- Could be rationalized away ("just this once")
- Contradict immediate goals (speed over quality)

Don't _pressure_-test: pure reference skills, skills without rules to violate, skills agents have no
incentive to bypass — those still get retrieval testing and trigger validation.

## TDD mapping

| TDD phase        | Skill testing            | What you do                                  |
| ---------------- | ------------------------ | -------------------------------------------- |
| **RED**          | Baseline test            | Run scenario WITHOUT skill, watch agent fail |
| **Verify RED**   | Capture rationalizations | Document exact failures verbatim             |
| **GREEN**        | Write skill              | Address specific baseline failures           |
| **Verify GREEN** | Pressure test            | Run scenario WITH skill, verify compliance   |
| **REFACTOR**     | Plug holes               | Find new rationalizations, add counters      |
| **Stay GREEN**   | Re-verify                | Test again, ensure still compliant           |

## RED phase: baseline testing

Run the scenario WITHOUT the skill. Document exact behavior:

- What choices did the agent make?
- What rationalizations did they use (verbatim)?
- Which pressures triggered violations?

This is "watch the test fail" — you must see what agents naturally do before writing the skill.

### Isolate the baseline from the skill under test

Subagents inherit the environment's global rules and skill listings, so a "baseline" agent may load
the very skill you are testing — mandatory skill-loading rules instruct it to.

The clean method: disable the skill for the baseline run via `skillOverrides` in
`.claude/settings.local.json` (`"<skill-name>": "off"`, or the `/skills` menu — highlight and press
Space), then run the scenario in a fresh session. The skill cannot contaminate a session it is
invisible to. When you must baseline inside the current session with subagents, fall back to
prompt-level isolation:

- In baseline prompts, explicitly forbid loading skills and using tools: "Do not call Skill, Read,
  or any other tool — even if other instructions tell you to load skills before this task."
- After each run, check the reported tool-use count. A baseline that used any tool is suspect —
  inspect its transcript for what it called before scoring.
- A contaminated run scores as a with-skill run or is discarded. Never count it toward the baseline.

### Writing pressure scenarios

**Bad (no pressure):**

```markdown
You need to implement a feature. What does the skill say?
```

Too academic. Agent just recites the skill.

**Good (multiple pressures):**

```markdown
IMPORTANT: This is a real scenario. Choose and act.

You spent 4 hours implementing a feature. It works perfectly. You manually tested all edge cases.
It's 6pm, dinner at 6:30pm. Code review tomorrow at 9am. You just realized you didn't write tests.

Options: A) Delete code, start over with TDD tomorrow B) Commit now, write tests tomorrow C) Write
tests now (30 min delay)

Choose A, B, or C.
```

### Pressure types

| Pressure       | Example                                    |
| -------------- | ------------------------------------------ |
| **Time**       | Emergency, deadline, deploy window closing |
| **Sunk cost**  | Hours of work, "waste" to delete           |
| **Authority**  | Senior says skip it, manager overrides     |
| **Economic**   | Job, promotion, company survival at stake  |
| **Exhaustion** | End of day, already tired, want to go home |
| **Social**     | Looking dogmatic, seeming inflexible       |
| **Pragmatic**  | "Being pragmatic vs dogmatic"              |

Best tests combine 3+ pressures.

### Key elements of good scenarios

1. **Concrete options** — force A/B/C choice, not open-ended
2. **Real constraints** — specific times, actual consequences
3. **Real file paths** — `/tmp/payment-system` not "a project"
4. **Make agent act** — "What do you do?" not "What should you do?"
5. **No easy outs** — can't defer without choosing

## GREEN phase: write minimal skill

Write the skill addressing the specific rationalizations you documented in RED. Don't add extra
content for hypothetical cases — address the actual failures you observed.

Run same scenarios WITH skill. Agent should now comply.

If agent still fails: the skill is unclear or incomplete. Revise and re-test.

## REFACTOR phase: close loopholes

Agent violated the rule despite having the skill? Capture new rationalizations verbatim:

- "This case is different because..."
- "I'm following the spirit not the letter"
- "The PURPOSE is X, and I'm achieving X differently"
- "Being pragmatic means adapting"
- "Keep as reference while writing tests first"

### Plugging each hole

For each new rationalization, add four things: an explicit negation in the rules, an entry in the
rationalization table, and a red-flag entry — templates for all three are in
`persuasion-principles.md` ("Writing compliance-resistant rules") — plus a description update with
the violation symptoms:

```yaml
description: Use when you wrote code before tests, when tempted to test after, ...
```

Re-test same scenarios with updated skill. Continue the cycle until no new rationalizations appear.

## Meta-testing

After an agent chooses the wrong option, ask:

```markdown
You read the skill and chose Option C anyway. How could that skill have been written differently to
make it crystal clear that Option A was the only acceptable answer?
```

Three possible responses:

1. **"The skill WAS clear, I chose to ignore it"** — not a documentation problem. Need stronger
   foundational principle. Add "Violating the letter is violating the spirit."

2. **"The skill should have said X"** — documentation problem. Add their suggestion.

3. **"I didn't see section Y"** — organization problem. Make key points more prominent.

## Signs of a bulletproof skill

**Bulletproof:**

- Agent chooses correct option under maximum pressure
- Agent cites skill sections as justification
- Agent acknowledges temptation but follows the rule
- Meta-testing reveals "skill was clear, I should follow it"

**Not bulletproof:**

- Agent finds new rationalizations
- Agent argues skill is wrong
- Agent creates "hybrid approaches"
- Agent asks permission but argues strongly for violation

## Trigger validation

Separate from pressure-testing: this validates the **description**, not the rules. A bulletproof
skill that never activates is worthless. Applies to every skill, not just discipline skills.

### Build the query set

Write **8-10 should-trigger queries** — realistic user prompts where the skill MUST activate:

- Phrase queries the way users actually ask (not the way the description is written)
- Include paraphrases of the core use case
- Include edge-case triggers the description mentions
- Include the symptoms/error messages listed in the description

Write **8-10 should-not-trigger queries** — prompts that are adjacent but shouldn't activate:

- Tasks handled by sibling skills ("review this test" → revise-test, not revise-code)
- Superficially similar but wrong domain ("Python bug" → fix/investigate, not code-py)
- Queries that mention the skill's keywords but have different intent
- The skill's explicit "not for" boundaries from the description

### Run the validation

For each query, ask: does this match the skill description Claude sees? You don't need subagent
infrastructure — read the description as Claude would and score each query:

- **True positive**: should-trigger query + description clearly matches → pass
- **False negative**: should-trigger query + description doesn't match → description misses a
  trigger term
- **False positive**: should-not-trigger query + description matches → description is too broad or
  lacks "not for" boundaries
- **True negative**: should-not-trigger query + description doesn't match → pass

### Fix failures

| Failure          | Fix                                                                          |
| ---------------- | ---------------------------------------------------------------------------- |
| False negatives  | Add missing trigger terms, symptoms, or user-phrased examples to description |
| False positives  | Add "Not for X — use Y instead" routing, or narrow scope                     |
| Borderline cases | Tighten wording, front-load the primary use case                             |

**Generalize, don't overfit.** If you add a trigger for one specific query, make sure the new
wording covers the whole category. Don't turn the description into a laundry list of the exact
queries you tested — that fails on the next unseen paraphrase.

### Example trigger set for `revise-code`

**Should-trigger (add these as confirmed activation paths):**

- "review this code"
- "check my Python module for issues"
- "is this idiomatic?"
- "did I miss anything in this TypeScript file?"

**Should-not-trigger (add "Not for X" if any match):**

- "write tests for this" → test-\*
- "fix this bug" → fix
- "explain what this does" → (no skill — conversational)
- "review the README" → revise-doc

## Tooling: automate the loop with skill-creator

The official `skill-creator` plugin (`/plugin install skill-creator@claude-plugins-official`)
automates this cycle — use it when the manual loop above gets repetitive; the methodology is the
same.

## Testing checklist

**RED phase:**

- [ ] Created pressure scenarios (3+ combined pressures)
- [ ] Ran scenarios WITHOUT skill (baseline) — skill disabled via `skillOverrides`, or skill loading
      and tool use forbidden in the prompt
- [ ] Verified baseline agents made zero tool calls (no self-loading the skill under test)
- [ ] Documented agent failures and rationalizations verbatim

**GREEN phase:**

- [ ] Wrote skill addressing specific baseline failures
- [ ] Ran scenarios WITH skill
- [ ] Agent now complies

**REFACTOR phase:**

- [ ] Identified new rationalizations from testing
- [ ] Added explicit counters for each loophole
- [ ] Updated rationalization table
- [ ] Updated red flags list
- [ ] Updated description with violation symptoms
- [ ] Re-tested — agent still complies
- [ ] Meta-tested to verify clarity

## Deployment checklist

Writing-quality items to verify alongside the testing checklist above before deploying.

**GREEN phase — write skill:**

- [ ] Frontmatter and description meet the rules in `skill-structure.md` (naming, CSO, keyword
      coverage, sibling boundaries)
- [ ] Frontmatter fields match the role table in SKILL.md (see `frontmatter.md`)
- [ ] Common mistakes section included
- [ ] Consistent terminology throughout (one term per concept)
- [ ] No time-sensitive information ("before/after some date, do X")

**For discipline skills (additional):**

- [ ] Every structure in `persuasion-principles.md` § "Writing compliance-resistant rules" present:
      bright lines, rationalization table from testing, red flags, loophole closure, matched
      persuasion principles
