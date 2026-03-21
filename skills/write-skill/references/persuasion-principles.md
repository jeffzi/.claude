# Persuasion Principles for Skill Design

## Contents

- [The seven principles](#the-seven-principles) — Authority, Commitment, Scarcity, Social proof,
  Unity, Reciprocity, Liking
- [Principle combinations by skill type](#principle-combinations-by-skill-type)
- [Why this works](#why-this-works)
- [Ethical use](#ethical-use)
- [Research citations](#research-citations)

---

LLMs respond to the same persuasion principles as humans. Understanding this psychology helps you
design skills that get followed under pressure — not to manipulate, but to ensure critical practices
are maintained.

**Research foundation:** Meincke et al. (2025) tested 7 persuasion principles with N=28,000 AI
conversations. Persuasion techniques more than doubled compliance rates (33% to 72%, p < .001).

## The seven principles

### 1. Authority

Deference to expertise, credentials, or official sources.

- Imperative language: "YOU MUST", "Never", "Always"
- Non-negotiable framing: "No exceptions"
- Eliminates decision fatigue and rationalization

**Use for:** discipline-enforcing skills, safety-critical practices, established best practices.

```markdown
# Strong (authority)

Write code before test? Delete it. Start over. No exceptions.

# Weak (no authority)

Consider writing tests first when feasible.
```

### 2. Commitment

Consistency with prior actions, statements, or public declarations.

- Require announcements: "Announce skill usage"
- Force explicit choices: "Choose A, B, or C"
- Use tracking for multi-step processes

**Use for:** ensuring skills are followed, multi-step processes, accountability.

```markdown
# Strong (commitment)

When you find a skill, you MUST announce: "I'm using [Skill Name]"

# Weak (no commitment)

Consider letting your partner know which skill you're using.
```

### 3. Scarcity

Urgency from time limits or limited availability.

- Time-bound requirements: "Before proceeding"
- Sequential dependencies: "Immediately after X"
- Prevents "I'll do it later"

**Use for:** immediate verification, time-sensitive workflows.

```markdown
# Strong (scarcity)

After completing a task, IMMEDIATELY request code review before proceeding.

# Weak (no scarcity)

You can review code when convenient.
```

### 4. Social proof

Conformity to what others do or what's considered normal.

- Universal patterns: "Every time", "Always"
- Failure modes: "X without Y = failure"
- Establishes norms

**Use for:** documenting universal practices, warning about common failures.

```markdown
# Strong (social proof)

Checklists without tracking = steps get skipped. Every time.

# Weak (no social proof)

Some people find tracking helpful for checklists.
```

### 5. Unity

Shared identity, "we-ness", in-group belonging.

- Collaborative language: "our codebase", "we're colleagues"
- Shared goals: "we both want quality"

**Use for:** collaborative workflows, establishing team culture.

```markdown
# Strong (unity)

We're colleagues working together. I need your honest technical judgment.

# Weak (no unity)

You should probably tell me if I'm wrong.
```

### 6. Reciprocity

Obligation to return benefits received. Use sparingly — can feel manipulative. Rarely needed in
skills.

### 7. Liking

Preference for cooperating with those we like. **Do not use for compliance** — conflicts with honest
feedback culture and creates sycophancy. Avoid for all discipline enforcement.

## Principle combinations by skill type

| Skill type           | Use                                   | Avoid               |
| -------------------- | ------------------------------------- | ------------------- |
| Discipline-enforcing | Authority + Commitment + Social Proof | Liking, Reciprocity |
| Guidance/technique   | Moderate Authority + Unity            | Heavy authority     |
| Collaborative        | Unity + Commitment                    | Authority, Liking   |
| Reference            | Clarity only                          | All persuasion      |

## Why this works

**Bright-line rules reduce rationalization:** "YOU MUST" removes decision fatigue. Absolute language
eliminates "is this an exception?" questions.

**Implementation intentions create automatic behavior:** "When X, do Y" is more effective than
"generally do Y." Clear triggers plus required actions reduce cognitive load on compliance.

**LLMs mirror human responses:** trained on human text containing these patterns. Authority language
precedes compliance in training data. Commitment sequences (statement then action) are frequently
modeled. Social proof patterns establish norms.

## Ethical use

**Legitimate:** ensuring critical practices are followed, creating effective documentation,
preventing predictable failures.

**Illegitimate:** manipulating for personal gain, creating false urgency, guilt-based compliance.

**The test:** would this technique serve the user's genuine interests if they fully understood it?

## Research citations

- **Cialdini, R. B. (2021).** _Influence: The Psychology of Persuasion (New and Expanded)._ Harper
  Business. Seven principles of persuasion; empirical foundation for influence research.
- **Meincke, L., Shapiro, D., Duckworth, A. L., Mollick, E., Mollick, L., & Cialdini, R. (2025).**
  Call Me A Jerk: Persuading AI to Comply with Objectionable Requests. University of Pennsylvania.
  Tested 7 principles with N=28,000 LLM conversations; compliance increased 33% to 72%.

## Attribution

Adapted from
[obra/superpowers/writing-skills](https://github.com/obra/superpowers/tree/main/skills/writing-skills)
by Jesse Vincent.
