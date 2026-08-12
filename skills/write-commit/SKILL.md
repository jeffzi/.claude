---
name: write-commit
description: >
  Use when writing git commit messages, reviewing
  commits before push, or about to commit during plan
  execution. Apply when tempted to write vague messages
  like "fix bug" or "update code", or when unsure
  whether a commit needs a body. Not for PR descriptions or changelog entries.
allowed-tools: Read, Grep, Bash(git *), AskUserQuestion
---

# Commit Messages

The diff shows what code changed. The commit message adds what the diff can't: the subject names the
**concrete effect**, the body explains **why** — motivation, reasoning, and context that vanish from
memory within weeks.

## Commit Scope

A commit serves one coherent purpose. When the changes to commit bundle genuinely unrelated work
(e.g. "upgrade dependencies AND add a new feature"), split it into separate commits; otherwise
prefer one commit with a subject that captures the overall purpose. Tests and implementation for the
same change are one coherent purpose — never split them into separate commits (e.g. a `test:` commit
followed by a `feat:` commit).

When and how often to commit is the caller's decision — an explicit user request, a standing grant,
or a workflow that prescribes its own commit sequencing. This skill governs the commit's content:
its message and what belongs in it. A workflow that owns staging chooses which unit of work each
commit covers and in what order — it never licenses splitting one unit's tests from its
implementation. A workflow instruction that contradicts a rule in this skill is a conflict to
surface to the user before committing, never resolved silently in either direction.

## Conventional Commits (required)

Every subject **must** follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```text
<type>(<scope>)!: <description>
```

- **type** (required): `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
  `chore`, `revert`.
- **scope** (optional): affected area in parens, e.g. `feat(auth):`.
- **!** (optional): marks a breaking change. A `BREAKING CHANGE:` (or `BREAKING-CHANGE:`) footer is
  optional when `!` is present, required when it isn't.
- **description**: lowercase, imperative, no trailing period (house rule — stricter than the spec).

**Footer syntax**: `<token>: <value>` or `<token> #<value>`. Multi-word tokens use hyphens
(`Acked-by`, `Refs`, `Reviewed-by`).

Examples: `fix(api): reject empty email on signup` · `feat!: drop node 18 support` ·
`refactor(parser): extract token stream helper`.

A commit without a valid type is invalid — rewrite before committing.

**Reverts**: use `revert: <subject of reverted commit>` and add a `Refs: <sha>` footer pointing to
the reverted commit. **Merge commits**: keep git's default `Merge …` subject — Conventional Commits
does not apply.

## Subject Lines

Keep the full subject (prefix + description) under **72 characters**; keep the description alone
under **50**. Describe the **concrete effect** — what changed from a user's perspective — not the
implementation steps. The body explains _why_; the subject explains _what happened_.

| Test                | How to apply                                                           |
| ------------------- | ---------------------------------------------------------------------- |
| `git log --oneline` | Would someone scanning 50 commits quickly include or exclude this one? |
| "If applied" test   | "If applied, this commit will ___" — meaningful to an outsider?        |

Scope to the affected area when not generic: `fix(net/http): handle foo when bar`.

| Implementation-focused (bad)                   | Effect-focused (good)                                  |
| ---------------------------------------------- | ------------------------------------------------------ |
| Refactor load_data() to use list comprehension | perf(loader): speed up CSV load by 40% on large files  |
| Change query to use index                      | perf(dashboard): fix 10-second page load               |
| Add import_key() function                      | feat(keys): import GPG keys via --import-key           |
| Fix BUG-9284                                   | fix(checkout): stop buy button disappearing on Mondays |
| Allow doc:sync on sensitive models             | fix(doc-sync): handle sensitive TOTP models            |

## Body

Most commits need only a subject line. **Skip the body** for single-purpose fixes, renames,
dependency bumps, small refactors — any change where the subject tells the full story.

**Never use the body to narrate the diff or justify bundling.** "Also does X, since both touch the
same file" restates what the diff shows and explains commit logistics, not motivation. If the only
thing the body would say is _what else is in this commit_ or _why things were grouped together_,
delete it — the subject and diff already cover that.

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

## No internal tooling leaks

Never reference skill names, agent names, phase IDs, `.planning/` paths, or any Claude-internal
process in commit messages. Scan every draft message before committing — if it contains any of
these, rewrite to describe the effect instead.

- **Bad**: `chore: run preflight checks` / `fix: resolve bug found during /tdd RED phase`
- **Good**: `fix: resolve lint errors` / `fix: reject empty email in form submission`

## Execution

Interactive commit requests — the user explicitly asked to commit, in any phrasing — follow
`references/interactive-flow.md`. A workflow that prescribes its own commit sequencing (e.g.
per-cycle TDD commits during plan execution) owns staging, approval, and timing itself: it uses the
message rules above only, and the interactive flow — its confirmation step included — does not
apply.

Pre-commit verification — tests, lint, type-check, and any verification the calling workflow
prescribes — is enforced by the global rules; it must pass **before** this skill is loaded.

## Red Flags — Stop Before Committing

- Running `git commit` on an interactive request without the user approving the final message
- Subject is "fix bug", "update code", "misc", a bare ticket ID, or "address review comments"
- Subject narrates the diff ("change X from 5 to 10") or reads as motivation ("Allow X on Y")
  instead of naming the concrete effect
- Body narrates the diff or justifies bundling ("also bumps X since both touch Y")
- Commit bundles unrelated changes that deserve separate commits
- Splitting tests from implementation into separate commits for the same feature/fix
- Referencing internal tooling (skill names, `.planning/` paths, agent names)

## Rationalization Guard

**Foundational principle:** Violating the letter of these rules is violating the spirit of the
rules.

| Excuse                           | Reality                                                                 |
| -------------------------------- | ----------------------------------------------------------------------- |
| "The diff is self-explanatory"   | Diffs show _what_, never _why_. Add the why.                            |
| "I'll remember the context"      | You won't, and your teammates never had it.                             |
| "The ticket has all the details" | Tickets get migrated, deleted, or go offline. Message must stand alone. |
| "It's just a small fix"          | Small fixes deserve clear subjects. "Fix X when Y" takes 5 seconds.     |
