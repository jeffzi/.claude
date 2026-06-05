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

Never expose internal tooling details (skill/agent names, `.planning/` paths, orchestrator
references) in commits, PRs, code comments, or any user-facing output. Describe **what was built or
fixed**, not the process.

### Verify before claiming completion

Never claim tests pass, builds succeed, or work is complete without running the verification command
and showing its output in the same message. "Should work" is not verification.

### Comment/docstring length and shape

Comments and docstrings — including new ones you write, not just existing ones — may be
multi-paragraph, use lists, code fences, section headers, and blank lines. Docstrings render as
markdown in most tooling; inline comments can follow the same rules when the content calls for it.

Do not:

- Collapse or reflow a multi-line comment/docstring into one line.
- Cram prose into one long line to avoid stacking `//`/`#` markers.
- Delete blank lines inside a docstring to make it "single-paragraph".
- Drop examples, caveats, or rationale to hit a length target.

"One short line max" elsewhere is aspirational and does not override this rule. The
default-no-comments guidance governs whether to write a comment; once warranted, length and
structure follow the content.
