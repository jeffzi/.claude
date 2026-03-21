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
- [Worked example: TDD skill](#worked-example-tdd-skill)
- [Testing checklist](#testing-checklist)

---

How to verify skills work under pressure using TDD methodology. This reference covers the full
testing cycle for discipline-enforcing and technique skills.

## When to test

Test skills that:

- Enforce discipline (TDD, testing requirements, verification steps)
- Have compliance costs (time, effort, rework)
- Could be rationalized away ("just this once")
- Contradict immediate goals (speed over quality)

Don't test: pure reference skills, skills without rules to violate, skills agents have no incentive
to bypass.

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

For each new rationalization, add four things:

**1. Explicit negation in rules:**

```markdown
Write code before test? Delete it. Start over.

**No exceptions:**

- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Delete means delete
```

**2. Entry in rationalization table:**

```markdown
| Excuse              | Reality                                                     |
| ------------------- | ----------------------------------------------------------- |
| "Keep as reference" | You'll adapt it. That's testing after. Delete means delete. |
```

**3. Red flag entry:**

```markdown
## Red flags — STOP

- "Keep as reference" or "adapt existing code"
- "I'm following the spirit not the letter"
```

**4. Update description with violation symptoms:**

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

## Worked example: TDD skill

**Initial test (failed):** Scenario: 200 lines done, forgot TDD, exhausted, dinner plans. Agent
chose C (write tests after). Rationalization: "Tests after achieve same goals."

**Iteration 1 — add counter:** Added section: "Why order matters." Re-tested: agent STILL chose C.
New rationalization: "Spirit not letter."

**Iteration 2 — add foundational principle:** Added: "Violating the letter is violating the spirit."
Re-tested: agent chose A (delete it). Cited the new principle directly. Meta-test: "Skill was clear,
I should follow it."

Bulletproof achieved after 2 REFACTOR iterations.

## Testing checklist

**RED phase:**

- [ ] Created pressure scenarios (3+ combined pressures)
- [ ] Ran scenarios WITHOUT skill (baseline)
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

## Attribution

Adapted from
[obra/superpowers/writing-skills](https://github.com/obra/superpowers/tree/main/skills/writing-skills)
by Jesse Vincent.
