# CLAUDE.md

## Rules

### Surface every verified issue — never skip silently, never report a maybe

**Surface every issue — never skip silently.** When you find and verify a bug, smell, or
inconsistency: stop, describe it, and ask once — one `Apply all N?` for the whole list, never a
per-item fix/defer/skip menu (`rules/no-unrequested-edits.md`). Non-zero exit codes are errors — fix
or surface before anything else; never switch files or approaches to avoid one. One exception: `ils`
exits 4 (pending: run `ils push` again) and 5 (delivered, not green: follow the last `Next:` line)
are verdicts, handled per the `ils` skill. Every other non-zero `ils` exit is an error under this
rule. Never attribute origin ("pre-existing", "not from this PR") — just diagnose and offer to fix.
Never run a baseline to establish origin: do not create worktrees, stash changes, or run any command
whose sole purpose is to prove a failure existed before your edits. Surface as a one-line finding —
never escalate an out-of-scope issue into a decision point or plan (`rules/decision-policy.md`).
During unattended plan execution (`<git-dir>/execute-plan-unattended` holds this session's id, or
the request named tasks of a plan file to implement), "stop" means append to the plan's Findings
list and continue — the findings lead the final report.

**An issue is a verified finding.** It exists only once you read the mechanism yourself (`file:line`
in context), the settling command's output is in context, or `claim-reviewer` returned
Verified/Refuted with score ≥ 75. Before that it is a hypothesis, and hypotheses never reach the
user — not as "one reading is still open", not as "could mean"/"might"/"likely"/"worth checking",
and not as a "clearly labeled unverified lead". Unsure, inferring, relying on a subagent's say-so,
or two subagents disagree → read the file or dispatch `claim-reviewer` (one claim per finding)
before writing the report. "Surface every issue" never licenses surfacing a maybe: dropping a
hypothesis you have not verified is not skipping. Time pressure or "just send what you have" means:
send the verified findings now, add one line "N items pending verification, follow-up in M minutes",
verify, then send only what held — never the unverified content. Full rule:
`rules/no-unverified-findings.md`.

### Approved plans execute to completion — never ask whether to continue

Approval of a plan is the request for every task in it. Execution runs to the Final Task with
one-line progress notes, never "should I continue?", "want me to launch the next task?", or a
progress summary that ends the turn. Only three things halt a plan: a gap the reviewer has refuted
twice (or a task's mechanical checks red), an unplanned behavior change something depends on, or a
destructive/cross-repo boundary. Protocol and flags: `Skill(execute-plan)`.

### No destructive operations without explicit permission

Never run any command that could destroy, overwrite, or discard uncommitted work. Always ask the
user first and explain why. Full operation list: `rules/no-destructive-ops.md`.

### Skill loading is mandatory — no exceptions

**Before every action in the skill-loading table (`rules/skill-loading.md`), load the skill first**
— every time, even if loaded earlier, even if already in plan mode, even after compaction. Plan mode
is system state; the skill is the instructions for using it. Editing a plan file without
`Skill(write-plan)` loaded is always wrong.

### Skill-prescribed agent dispatch is pre-approved

**Invoking a skill or command is the request for every agent it prescribes, in the number and
grouping it prescribes** — dispatch without asking, never do the work inline, never present inline
work as an agent's result. Agents you invent on your own initiative still need the user's request.
Full rule: `rules/skill-loading.md`.

### TDD

When the project has a test suite, no production code before a failing test. A test suite anywhere
in the project qualifies. No test suite at all → skip TDD.

- **Bug or regression** (unknown root cause): use `/fix` — it investigates first, then drives TDD. A
  bug report alone is read-only (`rules/no-unrequested-edits.md`); `/fix` requires a fix request.
- **New feature** (root cause irrelevant): load `Skill(tdd)` directly and start the red–green cycle.

Never dispatch `tdd-cycle` directly.

### Pre-commit hooks: `prek` or `lefthook`

TypeScript projects use `lefthook`. All other projects use `prek`. Never assume
`.pre-commit-config.yaml` means the `pre-commit` command exists.

### Lint suppressions: fix the code, not the config

Never add to an ignore list, disable a rule, or exclude a file to get a check passing — fix the
code. Suppress only genuine false positives, inline and with a reason. Config-level ignores require
explicit user approval. Full rule: `rules/lint-suppressions.md`.

### Scratchpad file references

When writing analysis or long output to a scratchpad file, run `open /path/to/file` via Bash
immediately after writing it — don't just print the command, execute it.

### No internal tooling leaks in user-facing output

Never expose internal tooling details (skill/agent names, `.planning/` paths, orchestrator
references) in commits, PRs, code comments, or any user-facing output. Describe **what was built or
fixed**, not the process.

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

**`ils` runs bare:** never piped, `tee`d, backgrounded, or behind `cd`, because a pipe hides the
exit code that carries the verdict. Running `ils push` again on exit 4 is not a re-run to filter
output: it asks GitHub for a verdict the first run did not get.

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
