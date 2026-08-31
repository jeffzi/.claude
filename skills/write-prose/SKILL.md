---
name: write-prose
description: |
  Use when writing or editing prose for clarity — "make this clearer", "tighten the prose". Not for
  document structure (write-doc) or removing AI-writing tells (em-dash overuse, rule of three).
argument-hint: "[text or file to edit]"
---

# Writing Clearly and Concisely

## Task

Edit `$ARGUMENTS` in place, applying the rules below. Report each change as `rule → before → after`.

## Rules

Check every rule on every edit. Mechanical usage rules (possessives, serial commas, comma splices,
fragments, dangling participles, parallelism, tense) are omitted deliberately — apply them silently,
they need no checklist.

1. **Use active voice**
2. **Put statements in positive form**
3. **Use definite, specific, concrete language**
4. **Omit needless words**
5. **Place emphatic words at end of sentence**
6. **Cap sentence length** — never exceed 30 words; aim for a document average of 15–20. One main
   idea per sentence; vary length — short sentences give relief.
7. **Keep subject and verb together** — never bury the verb under an inserted clause; move the aside
   to its own sentence.
8. **One term per concept** — repeat the term rather than switching to a synonym for variety.
   Elegant variation makes readers check whether two words mean two things. Normalize synonyms
   inherited from source material.

## Before/After Examples

**Active voice (Rule 1):**

- Before: "The configuration file is read by the parser at startup."
- After: "The parser reads the configuration file at startup."

**Positive form (Rule 2):**

- Before: "Do not use the old API unless you have no alternative."
- After: "Use the new API. Fall back to the old API only when the new one lacks a required feature."

**Concrete language (Rule 3):**

- Before: "The system experienced a significant degradation in performance."
- After: "Response latency increased from 50ms to 1200ms after the migration."
- Only use figures the source provides — never invent them. Without figures, tighten the phrasing
  instead ("performance degraded sharply").

**Omit needless words (Rule 4):**

- Before: "In order to establish a connection to the database, it is necessary to first configure
  the credentials."
- After: "Configure credentials before connecting to the database."

**Emphatic words at end (Rule 5):**

- Before: "Manual failover is error-prone, in most cases."
- After: "In most cases, manual failover is error-prone."

**Sentence cap (Rule 6):**

- Before: "Requests that fail the primary health check are retried against the secondary region
  after a backoff interval that grows exponentially, unless the circuit breaker has already opened,
  in which case they fail fast."
- After: "Requests that fail the primary health check retry against the secondary region with
  exponential backoff. If the circuit breaker is already open, they fail fast instead."

**Subject and verb together (Rule 7):**

- Before: "The scheduler, after checking every worker's heartbeat and pruning any that missed the
  timeout, assigns the next batch."
- After: "The scheduler checks every worker's heartbeat and prunes any that missed the timeout. Then
  it assigns the next batch."

**One term per concept (Rule 8):**

- Before: "The worker catches the exception. If the executor has attempts left, the agent re-runs
  the job."
- After: "The worker catches the exception. If it has attempts left, the worker re-runs the job."

## Anti-patterns

| Anti-pattern                                 | Why it fails                                                                                |
| -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| "This is a draft, style doesn't matter"      | Sloppy drafts become sloppy finals. Clarity during drafting catches logic gaps early.       |
| "Technical audiences don't care about style" | Technical readers care more — they scan under time pressure and ambiguity costs them hours. |
| "More words = more thorough"                 | Extra words dilute the signal. Readers skim past filler and miss the point.                 |
| "Passive voice sounds more professional"     | Passive voice hides the actor and weakens every sentence. Active voice is direct and clear. |

## Attribution

Reference material from [the-elements-of-style](https://github.com/obra/the-elements-of-style) by
Jesse Vincent.
