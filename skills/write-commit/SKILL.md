---
name: write-commit
description: >
  Use when writing git commit messages, reviewing
  commits before push, or about to commit during plan
  execution. Apply when tempted to write vague messages
  like "fix bug" or "update code", or when unsure
  whether a commit needs a body. Not for PR descriptions or changelog entries.
allowed-tools: Read, Grep, Bash(git *)
---

# Commit Messages

The diff shows what code changed. The commit message adds what the diff can't: the subject names the
**concrete effect**, the body explains **why** — motivation, reasoning, and context that vanish from
memory within weeks.

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
| Motivation test     | Does it read as "in order to ___"? Too abstract — name the effect.     |

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

## Anti-Patterns

| Pattern                                  | Problem                                                        |
| ---------------------------------------- | -------------------------------------------------------------- |
| "Fix bug", "update code", "misc"         | Zero information — forces everyone to read the diff            |
| "Fix JIRA-1234" (ticket only)            | Requires browser + tracker; breaks when tracker migrates       |
| "Change X from 5 to 10"                  | Narrates the diff — explain _why_ the constant changed         |
| "Allow X on Y" / "Enable X for Z"        | Reads as motivation, not effect — name what concretely changed |
| "Address review comments"                | Meaningless outside PR context                                 |
| Body narrates diff or justifies bundling | "Also bumps X since both touch Y" — logistics, not motivation  |
| Auto-committing during plan execution    | User loses ability to review before commit; hard to undo       |

## No internal tooling leaks

Never reference skill names, agent names, phase IDs, `.planning/` paths, or any Claude-internal
process in commit messages. Scan every draft message before committing — if it contains any of
these, rewrite to describe the effect instead.

- **Bad**: `chore: run preflight checks` / `fix: resolve bug found during /tdd RED phase`
- **Good**: `fix: resolve lint errors` / `fix: reject empty email in form submission`

## Execution

When the user **explicitly** asks to commit (in any phrasing — "commit", "commit changes", "commit
this"). **Never execute this during plan execution** — the user must review all changes first. An
explicit "commit" request during an active plan is not an exception to this rule.

Pre-commit verification (tests, lint, type-check) is enforced by the global rules — it must pass
**before** this skill is loaded. This skill owns message composition and the commit workflow, not
verification.

### Context (auto-injected)

!`git status 2>/dev/null`

!`git diff --cached --name-only 2>/dev/null`

!`git diff HEAD 2>/dev/null`

!`git branch --show-current 2>/dev/null`

!`git log --oneline -10 2>/dev/null`

1. **Review injected context** — the git state above is already available. Verify it matches
   expectations before composing the message.

2. **Compose the message** — apply all rules above before writing a single word of the subject.

3. **Stage** — before running `git add`, check what `git diff --cached --name-only` returned. If
   files are already staged that shouldn't be part of this commit, unstage them first with
   `git restore --staged <path>`. Then add only the intended files and confirm with
   `git diff --cached --name-only` before committing.

4. **Confirm** — use AskUserQuestion to present the composed message and staged files for approval.
   Options: "Commit" (proceed), "Edit message" (user provides revised wording), "Cancel" (abort).
   Never run `git commit` without the user approving the final message.

5. **Commit** — `git commit -m "..."` using a HEREDOC to preserve formatting.

6. **Verify** — immediately after `git commit`, run in parallel:
   - `git log --oneline -1` — confirm the commit SHA and subject match what was intended
   - `git show --stat HEAD` — confirm exactly the intended files appear in the commit, no more, no
     less

   If the commit SHA is absent (command failed silently), or the file list doesn't match what was
   staged, **stop and surface the discrepancy** before continuing. Do not proceed to the next commit
   or any subsequent step until this is resolved.

## Red Flags — Stop Before Committing

- Auto-committing without the user's explicit approval
- Writing a body that narrates the diff ("changed X to Y", "also bumps Z")
- Subject describes implementation steps instead of the concrete effect
- Commit bundles unrelated changes that deserve separate commits
- Referencing internal tooling (skill names, `.planning/` paths, agent names)
- Committing without fresh verification evidence in the current conversation

## Rationalization Guard

**Foundational principle:** Violating the letter of these rules is violating the spirit of the
rules.

A commit message that technically avoids the listed anti-patterns but still obscures intent violates
the spirit of these rules. If a future reader would need to open the diff to understand what
changed, the message has failed.

| Excuse                                                                  | Reality                                                                 |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| "The diff is self-explanatory"                                          | Diffs show _what_, never _why_. Add the why.                            |
| "I'll remember the context"                                             | You won't, and your teammates never had it.                             |
| "The ticket has all the details"                                        | Tickets get migrated, deleted, or go offline. Message must stand alone. |
| "It's just a small fix"                                                 | Small fixes deserve clear subjects. "Fix X when Y" takes 5 seconds.     |
| "The user asked me to commit, so auto-committing during a plan is fine" | Explicit commit request during a plan still requires user review first. |
