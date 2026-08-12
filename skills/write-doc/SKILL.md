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

## Before you write

### Identify your audience

Who will read this? What do they already know? What are they trying to do?

A new user installing your tool, a contributor reading your architecture, and an operator debugging
a failure at 3am are three different readers with three different needs. Write for the reader you
actually have, not an imagined universal audience.

### Choose the right document type (Diataxis)

If the document type isn't obvious from context, use AskUserQuestion to ask "What type of
documentation are you writing?" with the four types below as options.

Documentation serves four distinct purposes. Mixing them is the primary structural anti-pattern — it
produces docs that do none well.

| Type             | Purpose       | Reader's mindset              | Structure                             |
| ---------------- | ------------- | ----------------------------- | ------------------------------------- |
| **Tutorial**     | Learning      | "Teach me"                    | Step-by-step guided journey           |
| **How-to guide** | Doing         | "Help me accomplish X"        | Goal, prerequisites, steps, result    |
| **Reference**    | Looking up    | "What are the exact details?" | Comprehensive, structured, searchable |
| **Explanation**  | Understanding | "Why does it work this way?"  | Prose, context, trade-offs, history   |

Keep types separate. Reference that veers into tutorials, or tutorials that digress into
explanation, confuse the reader. Each type serves a different need.

Other document types don't fit the Diataxis grid but have their own structure: README (project
landing page), quickstart (a ruthlessly scoped tutorial variant — 3 minutes to the "aha moment"),
contributing guide, ADR, error messages, FAQ (supplement only — never primary docs), release notes.

Read `references/doc-types.md` for the document type you're writing — it has detailed templates and
examples for README, tutorial, how-to, reference, explanation, contributing guide, ADR, FAQ,
quickstart, and release notes. Error messages are covered below.

Read `references/writing-principles.md` for core principles (ARID, SKIMMABLE, EXEMPLARY, CONSISTENT,
CURRENT), structure principles, source principles, documentation prose rules, and accessibility
guidelines.

## Structure and formatting

### Heading hierarchy

Use headings to create a scannable outline. A reader should understand the page's structure from
headings alone. Don't nest deeper than H4 — if you need H5, the page is too long or needs splitting.

### Code examples

- Show working code. Code that almost works teaches the reader to distrust your docs.
- Use realistic names and values. `user_email = "alice@example.com"` teaches more than `x = "foo"`.
- Annotate non-obvious lines with comments. Don't comment the obvious.
- Show output when it helps — especially for CLI commands.

### Admonitions and callouts

Use sparingly. When everything is a warning, nothing is.

- **Note**: Extra context that's useful but not critical.
- **Tip**: A shortcut or best practice.
- **Warning**: Something that could cause problems if missed.
- **Caution/Danger**: Data loss, security risk, irreversible action.

If a page has more than 3-4 callouts, most of them should be regular prose.

## Error messages

Error messages are documentation at the point of failure. **Be Helpful, Be Human, Be Humble.**

- **Say what happened.** "Connection to database timed out after 30s" — not "An error occurred."
- **Say why.** "The host `db.example.com` is unreachable" — not just "Connection failed."
- **Say what to do.** "Check the database host in `config.yaml` and verify port 5432 is open."
- **Include specifics.** Show the actual values that failed (host, port, expected vs got).
- **Be brief.** Error messages are read under stress. Every extra word adds friction.
- **Don't blame the user.** "Invalid email format" — not "You entered an invalid email."

When documentation serves multiple audiences (e.g. developers and end users), identify what each
audience needs to act on and present that information prominently — not buried in supplementary
sections.

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

1. **Identify the type.** What is this — tutorial, reference, how-to? Apply the right structure.
2. **Check the audience.** Who is this for? Does the content match their knowledge level?
3. **Check skimmability.** Can someone find a specific answer in 30 seconds? If not, restructure.
4. **Check completeness.** Within its scope, does it cover everything? Partial coverage misleads.
5. **Check examples.** Are there code examples? Do they work? Are they realistic?
6. **Check prose.** Load `Skill(write-prose)` and apply every rule it states. Cut filler, fix
   passive voice.
7. **Check accessibility.** Alt text on images? Headings for screen readers? No color-only cues?
8. **Check currentness.** Are version numbers, links, and instructions still accurate?
9. **Check abbreviations.** All defined before first use?

## References

- `references/doc-types.md` — Detailed templates for each documentation type (except error messages,
  covered above)
- `references/writing-principles.md` — Content, structure, source principles; prose rules;
  accessibility and inclusivity guidelines
- `Skill(write-prose)` — Sentence-level prose clarity rules (Strunk's _Elements of Style_)
