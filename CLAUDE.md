# CLAUDE.md

## Rules

### Surface every issue — never skip silently

**Surface every issue — never skip silently.** When you find a bug, smell, or inconsistency: stop,
describe it, let the user decide (fix now, defer, or skip). Non-zero exit codes are errors — fix or
surface before anything else; never switch files or approaches to avoid one. Never attribute origin
("pre-existing", "not from this PR") — just diagnose and offer to fix. Never run a baseline to
establish origin: do not create worktrees, stash changes, or run any command whose sole purpose is
to prove a failure existed before your edits.

### No destructive operations without explicit permission

Never run any command that could destroy, overwrite, or discard uncommitted work. Always ask the
user first and explain why.

### TDD

When the project has a test suite, no production code before a failing test. A test suite anywhere
in the project qualifies. No test suite at all → skip TDD.

- **Bug or regression** (unknown root cause): use `/fix` — it investigates first, then drives TDD.
- **New feature** (root cause irrelevant): load `Skill(tdd)` directly and start the red–green cycle.

Never dispatch `tdd-cycle` directly.

### Pre-commit hooks: `prek` or `lefthook`

TypeScript projects use `lefthook`. All other projects use `prek`. Never assume
`.pre-commit-config.yaml` means the `pre-commit` command exists.

### No internal tooling leaks in user-facing output

Never expose internal tooling details (skill/agent names, GSD IDs, phase IDs, `.planning/` paths,
orchestrator references) in commits, PRs, code comments, or any user-facing output. Describe **what
was built or fixed**, not the process.

### Verify before claiming completion

Never claim tests pass, builds succeed, or work is complete without running the verification command
and showing its output in the same message. "Should work" is not verification.
