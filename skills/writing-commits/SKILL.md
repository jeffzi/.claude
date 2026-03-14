---
name: writing-commits
description: >
  Use when writing git commit messages, reviewing
  commits before push, or about to commit during plan
  execution. Apply when tempted to write vague messages
  like "fix bug" or "update code", or when unsure
  whether a commit needs a body.
---

# Commit Messages

The diff shows _what_ changed. The commit message's job is to explain _why_ — motivation, reasoning,
and context that vanish from memory within weeks.

## Commit Granularity

Default to **one commit per task**. A "task" is whatever unit of work serves one coherent purpose —
this includes multi-step plans when all steps contribute to the same goal. The user reviews all
changes before committing, so splitting into atomic commits adds friction without benefit — partial
staging (`git add -p`) is not available in this workflow.

Prefer a single commit with a clear subject line that captures the overall purpose. Only split into
multiple commits when a plan bundles genuinely unrelated work (e.g. "upgrade dependencies AND add a
new feature") — those are really separate tasks and deserve separate commits.

**Never auto-commit during plan execution.** The user must review all changes before any commit is
made. If a plan requires multiple commits, surface this during planning and get explicit approval.

## Subject Lines

Keep under **50 characters**. Describe **impact or purpose**, not implementation.

| Test                | How to apply                                                           |
| ------------------- | ---------------------------------------------------------------------- |
| `git log --oneline` | Would someone scanning 50 commits quickly include or exclude this one? |
| "If applied" test   | "If applied, this commit will ___" — meaningful to an outsider?        |

Scope to the affected area when not generic: `net/http: handle foo when bar`.

| Implementation-focused (bad)                   | Impact-focused (good)                            |
| ---------------------------------------------- | ------------------------------------------------ |
| Refactor load_data() to use list comprehension | Speed up data loading by 40% for large CSV files |
| Change query to use index                      | Fix 10-second page load on user dashboard        |
| Add import_key() function                      | Add support for importing GPG keys               |
| Fix BUG-9284                                   | Fix buy button disappearing on Mondays           |

## Body

Most commits need only a subject line. **Skip the body** for single-purpose fixes, renames,
dependency bumps, small refactors — any change where the subject tells the full story.

**Write a body** (1–3 sentences) when a future reader couldn't reconstruct the reasoning from the
diff alone:

- Non-obvious design choice (why this approach? alternatives rejected?)
- Change spanning multiple concerns
- Performance change (before/after numbers)
- Trade-offs future developers should understand

**Structure** around: **why** the change is necessary, **how** it addresses the issue (high-level,
not diff narration), and any **non-obvious effects**.

Summarize external context inline — don't assume access to issue trackers. Add ticket refs in a
footer, not as the message.

## Anti-Patterns

| Pattern                               | Problem                                                  |
| ------------------------------------- | -------------------------------------------------------- |
| "Fix bug", "update code", "misc"      | Zero information — forces everyone to read the diff      |
| "Fix JIRA-1234" (ticket only)         | Requires browser + tracker; breaks when tracker migrates |
| "Change X from 5 to 10"               | Narrates the diff — explain _why_ the constant changed   |
| "Address review comments"             | Meaningless outside PR context                           |
| Auto-committing during plan execution | User loses ability to review before commit; hard to undo |

## Rationalization Guard

| Excuse                           | Reality                                                                 |
| -------------------------------- | ----------------------------------------------------------------------- |
| "The diff is self-explanatory"   | Diffs show _what_, never _why_. Add the why.                            |
| "I'll remember the context"      | You won't, and your teammates never had it.                             |
| "The ticket has all the details" | Tickets get migrated, deleted, or go offline. Message must stand alone. |
| "It's just a small fix"          | Small fixes deserve clear subjects. "Fix X when Y" takes 5 seconds.     |
