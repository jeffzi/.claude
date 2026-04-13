---
name: write-prose
description: |
  Use when writing or editing any prose humans will read — documentation, commit messages, error
  messages, PR descriptions, UI text, reports, or explanations. Applies Strunk's writing rules for
  sentence-level clarity. Also use when the user says "make this clearer", "tighten the prose",
  "improve the writing", or when text feels bloated, passive, or vague. Covers sentence-level
  clarity, not document structure — for organizing documentation, use write-doc instead.
argument-hint: "[text or file to edit]"
model: sonnet
effort: medium
---

# Writing Clearly and Concisely

## Overview

William Strunk Jr.'s _The Elements of Style_ (1918) teaches you to write clearly and cut ruthlessly.

## All Rules

### Elementary Rules of Usage (Grammar/Punctuation)

1. Form possessive singular by adding 's
2. Use comma after each term in series except last
3. Enclose parenthetic expressions between commas
4. Comma before conjunction introducing co-ordinate clause
5. Don't join independent clauses by comma
6. Don't break sentences in two
7. Participial phrase at beginning refers to grammatical subject

### Elementary Principles of Composition

1. One paragraph per topic
2. Begin paragraph with topic sentence
3. **Use active voice**
4. **Put statements in positive form**
5. **Use definite, specific, concrete language**
6. **Omit needless words**
7. Avoid succession of loose sentences
8. Express co-ordinate ideas in similar form
9. **Keep related words together**
10. Keep to one tense in summaries
11. **Place emphatic words at end of sentence**

## Before/After Examples

**Active voice (Rule 3):**

- Before: "The configuration file is read by the parser at startup."
- After: "The parser reads the configuration file at startup."

**Positive form (Rule 4):**

- Before: "Do not use the old API unless you have no alternative."
- After: "Use the new API. Fall back to the old API only when the new one lacks a required feature."

**Omit needless words (Rule 6):**

- Before: "In order to establish a connection to the database, it is necessary to first configure
  the credentials."
- After: "Configure credentials before connecting to the database."

**Concrete language (Rule 5):**

- Before: "The system experienced a significant degradation in performance."
- After: "Response latency increased from 50ms to 1200ms after the migration."

## Anti-patterns

| Anti-pattern                                 | Why it fails                                                                                |
| -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| "This is a draft, style doesn't matter"      | Sloppy drafts become sloppy finals. Clarity during drafting catches logic gaps early.       |
| "Technical audiences don't care about style" | Technical readers care more — they scan under time pressure and ambiguity costs them hours. |
| "More words = more thorough"                 | Extra words dilute the signal. Readers skim past filler and miss the point.                 |
| "Passive voice sounds more professional"     | Passive voice hides the actor and weakens every sentence. Active voice is direct and clear. |

## Bottom Line

Writing for humans? Apply the rules above. Dispatch a subagent with the draft and these rules to
copyedit when context is tight.

## Attribution

Reference material from [the-elements-of-style](https://github.com/obra/the-elements-of-style) by
Jesse Vincent.
