---
name: write-doc
description: |
  Use when creating, editing, or reviewing documentation — READMEs, tutorials, how-to guides,
  reference docs, API docs, contributing guides, architecture decision records, error messages,
  release notes, or any prose-heavy technical document meant for human readers. Also use when the
  user asks to "write docs" or "document this", or asks about documentation structure, information
  architecture, or doc best practices. Does not cover inline code docstrings — those belong to
  language-specific skills like code-py, code-ts. Not for CHANGELOG.md files — use write-changelog.
  Not for reviewing an existing doc and fixing what the review finds — use revise-doc. For
  sentence-level prose clarity, use write-prose instead.
argument-hint: "[doc type or target file]"
---

# Writing Documentation

Documentation exists to help someone accomplish something. Every sentence either helps the reader or
wastes their time.

## Identify your audience

Who will read this, what do they already know, what are they trying to do? A new user installing
your tool, a contributor reading your architecture, and an operator debugging a failure at 3am are
different readers with different needs. Write for the reader you actually have, not an imagined
universal audience. When one document serves multiple audiences (e.g. developers and end users),
identify what each audience needs to act on and present it prominently — not buried in supplementary
sections.

## Choose the right document type (Diataxis)

If the document type isn't obvious from context, use AskUserQuestion to ask "What type of
documentation are you writing?" with the four types below as options.

| Type             | Purpose       | Reader's mindset              | Structure                             |
| ---------------- | ------------- | ----------------------------- | ------------------------------------- |
| **Tutorial**     | Learning      | "Teach me"                    | Step-by-step guided journey           |
| **How-to guide** | Doing         | "Help me accomplish X"        | Goal, prerequisites, steps, result    |
| **Reference**    | Looking up    | "What are the exact details?" | Comprehensive, structured, searchable |
| **Explanation**  | Understanding | "Why does it work this way?"  | Prose, context, trade-offs, history   |

Documentation serves four distinct purposes; mixing them is the primary structural anti-pattern — it
produces docs that do none well. **Keep types separate.** Reference that veers into tutorials, or
tutorials that digress into explanation, confuse the reader.

Types outside the grid have their own structure: README, quickstart (a ruthlessly scoped tutorial
variant), contributing guide, ADR, FAQ, release notes, error messages.

Read `references/doc-types.md` for the template of the type you're writing — README, tutorial,
how-to, reference, explanation, contributing guide, ADR, FAQ, quickstart, release notes, and error
messages.

Read `references/writing-principles.md` for core principles (ARID, SKIMMABLE, EXEMPLARY, CONSISTENT,
CURRENT), structure and formatting rules (headings, code examples, admonitions), prose rules, and
accessibility guidelines.

## Anti-patterns

Further anti-patterns (minimizing language, bare links, screenshots of text, partial coverage, stale
docs) live in `references/writing-principles.md`.

| Pattern                              | Problem                                                         |
| ------------------------------------ | --------------------------------------------------------------- |
| Wall of text with no headings        | Nobody reads it. Readers scan; prose blocks get skipped.        |
| Starting with installation           | Open with _what it does and why_ before _how to install_.       |
| FAQ as primary documentation         | FAQs accumulate junk and bypass proper structure.               |
| "See above" / "As mentioned earlier" | Readers land mid-page from search. They didn't read above.      |
| Documenting internals as user docs   | Users don't care about your class hierarchy. Document behavior. |
| Undefined abbreviations              | Never assume the reader knows your acronyms.                    |

## When reviewing existing docs

Answer every row before reporting — a skipped row is a check that failed; each answer names the file
location it applies to.

| Check         | Question                                                                                 |
| ------------- | ---------------------------------------------------------------------------------------- |
| Type          | Tutorial, reference, how-to? Apply the right structure.                                  |
| Audience      | Who is this for? Does content match their knowledge level?                               |
| Skimmability  | Can someone find a specific answer in 30 seconds? If not, restructure.                   |
| Completeness  | Within its scope, does it cover everything? Partial coverage misleads.                   |
| Examples      | Are there code examples? Do they work? Are they realistic?                               |
| Prose         | Load `Skill(write-prose)` and apply every rule it states. Cut filler, fix passive voice. |
| Accessibility | Alt text on images? Headings for screen readers? No color-only cues?                     |
| Currentness   | Version numbers, links, and instructions still accurate?                                 |
| Abbreviations | All defined before first use?                                                            |
