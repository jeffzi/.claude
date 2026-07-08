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

### Skill loading is mandatory — no exceptions

**Before every action in the skill-loading table (`rules/skill-loading.md`), load the skill first.**
Plan mode = `Skill(write-plan)`. Writing code = `Skill(code-core)`. Tests = `Skill(test-core)`.
Every time, even if loaded earlier, even if already in plan mode, even after compaction. "Already in
plan mode" does not mean the skill is loaded — plan mode is system state, the skill is the
instructions for how to use it. Editing a plan file without the skill loaded is always wrong.

### TDD

When the project has a test suite, no production code before a failing test. A test suite anywhere
in the project qualifies. No test suite at all → skip TDD.

- **Bug or regression** (unknown root cause): use `/fix` — it investigates first, then drives TDD.
- **New feature** (root cause irrelevant): load `Skill(tdd)` directly and start the red–green cycle.

Never dispatch `tdd-cycle` directly. Exception: build's FAIL-path remediation may dispatch
`tdd-cycle` directly when the TDD context (`TEST_COMMAND`, `TEST_FILE`, etc.) is already present
from a prior `tdd` run.

### Pre-commit hooks: `prek` or `lefthook`

TypeScript projects use `lefthook`. All other projects use `prek`. Never assume
`.pre-commit-config.yaml` means the `pre-commit` command exists.

### No internal tooling leaks in user-facing output

Never expose internal tooling details (skill/agent names, `.planning/` paths, orchestrator
references) in commits, PRs, code comments, or any user-facing output. Describe **what was built or
fixed**, not the process.

### No `ponytail:` comments

Never add `ponytail:` comments to code. These are internal markers from the `/ponytail-review` skill
and must not appear in committed code.

### Never re-run a command to filter output you already have

If command output is already in context, extract what you need from it — don't re-execute. When you
anticipate needing to examine output multiple ways, capture it once with `tee`:

```bash
<command> 2>&1 | tee /tmp/out.txt | tail -30
# later, if needed:
grep -E "..." /tmp/out.txt
```

Re-running a command solely to change the filter is always wrong: it wastes time, doubles side
effects.

**Background commands:** the completion notification carries only the exit code — the output is not
in context. Always `tee` to a file when running a command in the background, then `Read` the file on
completion instead of re-running:

```bash
# run_in_background: true
<command> 2>&1 | tee /tmp/out.txt
# on notification: Read /tmp/out.txt — never re-run
```

### Verify before claiming completion

Never claim tests pass, builds succeed, or work is complete without running the verification command
and showing its output in the same message. "Should work" is not verification.

**This includes commits.** Never commit until the full verification suite has run and passed — the
order is implement → verify → commit, never implement → commit → verify. One failing check means no
commit.

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
