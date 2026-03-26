---
name: write-prose
description: |
  Use when writing or editing any prose humans will read — documentation, commit messages, error
  messages, PR descriptions, UI text, reports, or explanations. Applies Strunk's writing rules for
  sentence-level clarity. Also use when the user says "make this clearer", "tighten the prose",
  "improve the writing", or when text feels bloated, passive, or vague. Covers sentence-level
  clarity, not document structure — for organizing documentation, use write-doc instead.
---

# Writing Clearly and Concisely

## Overview

William Strunk Jr.'s _The Elements of Style_ (1918) teaches you to write clearly and cut ruthlessly.

**WARNING:** `elements-of-style.md` consumes ~12,000 tokens. Read it only when writing or editing
prose.

## When to Use This Skill

Use this skill whenever you write prose for humans:

- Documentation, README files, technical explanations
- Commit messages, pull request descriptions
- Error messages, UI copy, help text, comments
- Reports, summaries, or any explanation
- Editing to improve clarity

**If you're writing sentences for a human to read, use this skill.**

## Limited Context Strategy

When context is tight:

1. Write your draft using judgment
2. Dispatch a subagent with your draft and `elements-of-style.md`
3. Have the subagent copyedit and return the revision

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

### Section V: Words and Expressions Commonly Misused

Alphabetical reference for usage questions

## Bottom Line

Writing for humans? Read `elements-of-style.md` and apply the rules. Low on tokens? Dispatch a
subagent to copyedit with the guide.

## Attribution

Reference material from [the-elements-of-style](https://github.com/obra/the-elements-of-style) by
Jesse Vincent.
