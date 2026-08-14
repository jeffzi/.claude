# Document Type Templates

Detailed patterns and templates for common documentation types. Read the section relevant to the
document you're writing.

## Contents

- [README](#readme)
- [Tutorial](#tutorial)
- [How-to Guide](#how-to-guide)
- [Reference](#reference)
- [Explanation](#explanation)
- [Contributing Guide](#contributing-guide)
- [Architecture Decision Record (ADR)](#architecture-decision-record-adr)
- [FAQ](#faq)
- [Quickstart](#quickstart)
- [Release Notes](#release-notes)
- [Error Messages](#error-messages)

---

## README

The README is a project's landing page. Readers arrive with one question: "What is this and should I
care?" Answer that before anything else.

### README structure

```markdown
# Project Name

One-sentence description of what it does and who it's for.

## What it does

2-3 sentences on the problem it solves. Not how — what and why.

## Quick example

    // The simplest realistic usage — something someone would actually do.
    import project
    project.do_stuff()

## Installation

Shortest path to running code. One command if possible. Link to detailed instructions for complex
setups.

## Usage

Common use cases with code examples. Not exhaustive — show the 80% case.

## Documentation

Link to full docs if they exist separately.

## Contributing

Brief pointer to CONTRIBUTING.md or inline instructions.

## License

State the license. Link to LICENSE file.
```

### README principles

- **Lead with value.** What problem does this solve? Why should I use this instead of X? Answer
  before asking the reader to install anything.
- **Show, don't tell.** A code example communicates faster than a feature list. "Runs 10x faster"
  means less than a benchmark table.
- **Honest about limitations.** State what it does NOT do. This saves the reader from investing time
  in something that won't meet their needs.
- **Minimize prerequisite reading.** The README should be self-contained for the basic case. Don't
  require the reader to go elsewhere to understand what the project does.

---

## Tutorial

A tutorial guides a beginner through a learning experience. The reader has no prior knowledge of the
topic and is learning by doing.

### Tutorial structure

```markdown
# Tutorial: [What the reader will learn]

## What you'll build / learn

Brief description of the end result. Show a screenshot or example output if visual.

## Prerequisites

What the reader needs before starting. Be specific about versions.

## Step 1: [Action verb describing the step]

Explanation of what this step does and why.

[Code or instructions]

Expected result: [What the reader should see]

## Step 2: ...

## Step N: ...

## What you've learned

Recap of concepts covered. Pointers to next steps (how-to guides, reference docs).
```

### Tutorial principles

- **The reader is the hero, not the technology.** Frame steps as actions the reader takes, not
  features the software has. "You'll configure..." not "The software supports..."
- **Every step must work.** Test the tutorial end-to-end. A broken step at minute 20 wastes all the
  time the reader invested.
- **Show expected results after each step.** The reader needs confirmation they're on track. "You
  should see:" followed by example output prevents confusion from compounding.
- **Minimum viable scope.** Teach one thing. A tutorial that covers authentication, database setup,
  and deployment teaches none of them well.
- **Explain just enough.** Provide context for why each step matters, but don't digress into theory.
  Link to explanation docs for deeper understanding.

---

## How-to Guide

A how-to guide helps an experienced reader accomplish a specific task. Unlike a tutorial, it assumes
the reader has context and just needs directions.

### How-to guide structure

```markdown
# How to [accomplish specific goal]

Brief context: when you'd need to do this.

## Prerequisites

- What must be in place before starting (specific versions, access, config)

## Steps

### 1. [Action verb]

[Instruction]

### 2. [Action verb]

[Instruction]

## Verification

How to confirm the task succeeded.

## Troubleshooting (optional)

Common problems and their solutions.
```

### How-to guide principles

- **Task-oriented, not concept-oriented.** Start from the reader's goal, not from the technology's
  architecture. "How to deploy to staging" — not "Understanding the deployment pipeline."
- **No teaching.** The reader already knows the concepts. They need steps, not theory. Link to
  explanations for readers who need background.
- **Flexible, not rigid.** Acknowledge that the reader's situation may differ. "If you're using X
  instead of Y, adjust the config path accordingly" — but don't enumerate every possible variation.

---

## Reference

Reference documentation is the source of truth for details. Readers arrive knowing roughly what they
need — they're looking up the specifics.

### Reference structure

Varies by what you're documenting:

**API Reference:**

```markdown
## endpoint_or_function_name

Brief description of what it does.

### Parameters

| Name       | Type   | Required | Description  |
| ---------- | ------ | -------- | ------------ |
| param_name | string | Yes      | What it does |

### Returns

Description of the return value, with example.

### Errors

| Code | Meaning            |
| ---- | ------------------ |
| 404  | Resource not found |

### Example

[Working code example]
```

**Configuration Reference:**

```markdown
## setting_name

Type: string | Default: "value"

Description of what it controls and when you'd change it.
```

**CLI Reference:**

```markdown
## command-name

Description of what the command does.

### Synopsis

    command-name [options] <required-arg> [optional-arg]

### Options

    --flag, -f    Description of what it does (default: value)

### Examples

    $ command-name --flag value
    Expected output
```

### Reference principles

- **Comprehensive within its scope.** If you document 9 out of 10 flags, the reader won't know if
  the 10th was omitted or doesn't exist. Cover everything or state what's excluded.
- **Consistent structure.** Every entry should have the same sections in the same order. Pattern
  recognition speeds up lookup.
- **Accurate above all.** Reference docs are a contract. If the docs say the default is 30s and the
  code uses 60s, the docs are lying and the reader will debug a phantom issue.
- **Dry is fine.** Reference docs don't need personality. Clarity and accuracy are the goals. Save
  the narrative for explanations.

---

## Explanation

Explanation docs provide context, background, and reasoning. They answer "why?" and "how does this
fit together?"

### Explanation structure

```markdown
# [Concept or topic]

Opening that frames the topic and why it matters to the reader.

## Background / context

What the reader needs to know to understand this topic.

## How it works

The core explanation, with diagrams if helpful.

## Design decisions and trade-offs

Why it works this way and not another way. What alternatives were considered and rejected.

## Implications

What this means for the reader's work. How it affects related topics.

## Further reading

Links to related explanations, tutorials, and reference docs.
```

### Explanation principles

- **Context over instructions.** Explanations help the reader build a mental model. They don't tell
  the reader what to do — that's what how-to guides are for.
- **Acknowledge trade-offs.** Real engineering involves trade-offs. "We chose X because of
  constraint Y, at the cost of Z" is more useful than presenting X as the only option.
- **Diagrams help.** Architecture, data flow, and state machine diagrams often communicate
  relationships more clearly than prose.
- **Connect to other docs.** Explanations are the glue between tutorials, how-tos, and references.
  Link freely.

---

## Contributing Guide

A contributing guide removes barriers for people who want to help. It sets expectations and prevents
friction.

### Contributing guide structure

```markdown
# Contributing to [Project]

Brief welcome. What kinds of contributions are valued (code, docs, bug reports, design, etc.).

## Getting started

### Development setup

How to set up a local development environment. Step by step.

### Running tests

How to run the test suite.

## How to contribute

### Reporting bugs

What to include in a bug report (steps to reproduce, expected vs actual, environment details).

### Suggesting features

Where and how to propose features. What information helps the maintainers evaluate proposals.

### Submitting changes

1. Fork and branch workflow (or whatever the project uses)
2. Coding standards and style
3. Commit message conventions
4. How to open a pull request
5. What happens after you open a PR (review process, timeline)

## Code of conduct

Link to or state the code of conduct.
```

### Contributing guide principles

- **Lower the barrier.** Assume the reader has never contributed to an open-source project. Spell
  out steps that seem obvious to you.
- **Set expectations about response time.** "We aim to review PRs within a week" prevents
  contributors from wondering if their PR was ignored.
- **Separate concerns.** Bug reports, feature requests, and code contributions are different
  workflows. Don't blend them.

---

## Architecture Decision Record (ADR)

An ADR captures a significant technical decision, its context, and its consequences. ADRs create a
decision log that future developers can consult to understand _why_ things are the way they are.

### ADR structure

```markdown
# ADR-NNN: [Decision title]

Date: YYYY-MM-DD Status: proposed | accepted | deprecated | superseded by ADR-NNN

## Context

What situation or problem prompted this decision? What constraints apply?

## Decision

What was decided. State it clearly and directly.

## Consequences

What follows from this decision — both positive and negative. What trade-offs were accepted? What
new constraints does this create?

## Alternatives considered (optional)

Other options that were evaluated and why they were rejected.
```

### ADR principles

- **One decision per ADR.** Don't bundle multiple decisions. Each should stand alone.
- **Capture context, not just the choice.** The decision itself is in the code. The ADR's value is
  the _why_ — the constraints, trade-offs, and alternatives that won't be visible a year from now.
- **Immutable once accepted.** Don't edit old ADRs. If a decision changes, write a new ADR that
  supersedes the old one. The history of decisions is itself valuable.

---

## FAQ

FAQs work as supplementary documentation — a parking lot for questions that don't fit elsewhere.
They fail as primary documentation.

### When FAQs work

- Genuinely common questions from real users (support tickets, forum posts, issue trackers).
- Short answers that would be buried in longer documents.
- Topics that span multiple document types.

### When FAQs fail

- As a dumping ground for miscellaneous content.
- As a substitute for proper tutorials or how-to guides.
- When the "questions" were never actually asked by real users.

### FAQ principles

- **Source questions from real data.** Search queries, support tickets, and forum posts tell you
  what users actually ask. Don't invent questions.
- **Keep answers short.** If an answer grows past a paragraph, it belongs in its own how-to or
  explanation page. Link to it.
- **Review regularly.** FAQs decay faster than other docs. Remove questions that are no longer
  relevant. Update answers when the product changes.

---

## Quickstart

A quickstart is a ruthlessly focused tutorial — the fastest path to seeing the product work. Target
roughly 3 minutes. The reader should reach the "aha moment" with zero decision-making.

### Quickstart structure

```markdown
# Quickstart

## Prerequisites

Absolute minimum requirements (ideally just one or two).

## Step 1: Install

Single command.

## Step 2: Run

Single command or minimal code block.

## Expected result

What the reader should see. Screenshot or output.

## Next steps

Links to the full tutorial and documentation.
```

### Quickstart principles

- **One path, no choices.** Remove all decision points — pick the most common case and hard-code it.
  "Create a file called `app.py`" — not "Choose your preferred filename."
- **Working in 3 minutes.** If it takes longer, cut scope. The reader can explore depth in
  tutorials.
- **Show the result.** The reader needs to see something work. A visible output builds confidence.
- **No explanation.** Save the "why" for tutorials and explanations. A quickstart is pure "do this,
  see that."

---

## Release Notes

Release notes tell users what changed and what they need to do about it.

### Release notes structure

Each entry should answer:

1. **What changed?** Concrete description of the change.
2. **Why does it matter?** Impact on the user — not the internal motivation.
3. **What should the user do?** Migration steps, configuration changes, or "nothing."

### Release notes principles

- **Group by impact, not by implementation.** "Breaking changes," "New features," "Bug fixes" — not
  "Backend changes," "Frontend changes."
- **Be specific.** "Fixed login failing when email contains a plus sign" — not "Various bug fixes."
- **Link to details.** Keep the release note brief. Link to the relevant doc, PR, or migration guide
  for full context.
- **For bug fixes, use CCFR.** The Cause-Consequence-Fix-Result template works well:
  - **Cause**: What triggered the bug
  - **Consequence**: What users experienced
  - **Fix**: What was changed
  - **Result**: What users should see now

---

## Error Messages

Error messages are documentation at the point of failure. **Be Helpful, Be Human, Be Humble.**

- **Say what happened.** "Connection to database timed out after 30s" — not "An error occurred."
- **Say why.** "The host `db.example.com` is unreachable" — not just "Connection failed."
- **Say what to do.** "Check the database host in `config.yaml` and verify port 5432 is open."
- **Include specifics.** Show the actual values that failed (host, port, expected vs got).
- **Be brief.** Error messages are read under stress. Every extra word adds friction.
- **Don't blame the user.** "Invalid email format" — not "You entered an invalid email."
