# CLAUDE.md

This is the global Claude Code configuration directory.

## Directory layout

```text
skills/          # SKILL.md definitions (code-py, tdd, write-doc, etc.)
agents/          # Subagent definitions (tdd-red, tdd-green, gsd-*, code-distill, etc.)
commands/        # Slash commands (gsd/*, preflight, vet-code, vet-test, upgrade-*)
hooks/           # Pre/post hooks (git-safety, worktree-safety, skill-loader, etc.)
scripts/         # Helper scripts
plugins/         # Third-party plugin cache
projects/        # Per-project memory and settings
get-shit-done/   # GSD workflow engine (commands, agents, skills)
settings.json    # Shared settings (permissions, env vars, MCP servers)
settings.local.json # Local-only settings (gitignored)
```

## Rules

### Surface every issue you notice — never skip silently

When you discover a bug, code smell, improvement opportunity, or inconsistency during work, you
**MUST** stop and surface it to the user. Never silently work around it, skip it, or fix it without
asking. The user decides whether to fix now, defer, or skip — not you.

**Non-zero exit codes are errors. Period.** If a command fails (build, test, lint, any tool), you
MUST fix it or surface it before doing anything else. You may NOT switch to a different file,
different config, or different approach to avoid the error. The error exists; deal with it first.
"It's pre-existing" and "I'll use a different config" are both workarounds — blocked below.

This rule **overrides** any instruction to "not go beyond what was asked" or "don't make
improvements beyond the task." Surfacing an issue is not scope creep — it is the minimum
expectation. Silently skipping an issue you noticed is always wrong, regardless of what the current
task is.

**Protocol when you notice an issue:**

1. **Stop** — do not continue past the issue without addressing it.
2. **Describe** — tell the user what you found, why it matters, and what the fix would be.
3. **Ask** — let the user decide: fix now, defer, or skip.
4. **Only then continue** — with whatever the user chose.

**Zero blame attribution.** Never comment on who or what introduced a bug. Present the diagnosis and
offer to fix — nothing else. If your draft contains a clause that assigns origin, delete the clause.

**Rationalizations to block** — if you think any of these, STOP and surface the issue instead:

| Excuse                                            | Reality                                         |
| ------------------------------------------------- | ----------------------------------------------- |
| "This isn't part of the task"                     | Surfacing it IS part of every task. Ask.        |
| "This isn't from my changes"                      | Irrelevant. You noticed it, surface it.         |
| "This is a pre-existing bug"                      | Now you've seen it. Surface it.                 |
| "This is unrelated to [current task]"             | You found it during [current task]. Surface it. |
| "This is outside the scope"                       | Surfacing is never outside scope. Ask.          |
| "I'll just work around it"                        | Workarounds hide problems. Surface it.          |
| "Let me add a quick workaround"                   | Investigate the root cause. Surface it.         |
| "Let me use a different file/config/approach"     | That's a workaround. Fix the failing one first. |
| "Let me revert and leave it as-is"                | Don't give up. Surface the real issue.          |
| "That was already there / inherent / unavoidable" | Reworded deflection. Investigate alternatives.  |
| "My fix didn't cause this new issue"              | The user reported a problem. Fix it.            |
| "I shouldn't refactor this (not my code)"         | You noticed a problem. Surface it and ask.      |

### No destructive operations without explicit permission

Never run any command that could destroy, overwrite, or discard uncommitted work. Always ask the
user first and explain why. This includes but is not limited to:

- **Git (discarding changes)**: `checkout --`, `checkout -f`/`--force`, `switch -f`/`--force`/
  `--discard-changes`, `restore` (without `--staged`), `reset` (all forms including `reset HEAD`),
  `clean`, `stash`, `apply -R`/`--reverse`. To unstage files, use `git restore --staged <path>`
  instead of `git reset`.
- **Git (rewriting history / bypassing safeguards)**: `commit --amend`, `push --force`, `rebase`
  (with uncommitted changes), `branch -D`, `--no-verify` on any command.
- **Git (tracking ignored files)**: `add -f`/`--force` on gitignored files. Never force-add files
  that match a local or global gitignore rule.
- **File overwriting**: Reading content from git history (`git show`, `git cat-file`) and writing it
  back via Write/Edit tools or shell redirects (`git show HEAD:file > file`) to revert a file.
- **File deletion**: `rm`, `rm -rf`, `unlink`, or any command that removes files.
- **Shell redirects**: Truncating files via `> file` or `echo "" > file`.
- **Worktrees**: `git worktree remove` or `ExitWorktree` when the worktree has uncommitted changes.
  Always commit work before leaving a worktree.

### Worktree compression recovery

**After context compression while in a worktree**, you have lost context about work already done.
Before taking ANY action:

1. Run `git status` to see uncommitted changes.
2. Run `git log --oneline -10` to see recent commits on the branch.
3. Run `git diff --stat` to see what files are modified.
4. **Continue from where you left off** — do NOT restart the plan from scratch.

If you see work already done (commits, staged/unstaged changes), that's YOUR prior work. Restarting
the plan from step 1 would destroy it. Pick up where you left off based on the git state.

If a worktree already exists at the expected path, enter it and continue — never remove and recreate
it.

### TDD

When asked to fix a bug or implement a feature/behavior change and the project has a test suite, you
**MUST** follow TDD. Do NOT touch production code until a failing test proves the need. No
exceptions. If the project has no test suite at all, TDD does not apply — just write the code
directly.

One behavior group at a time: write tests for a single concern or a cohesive batch of related
concerns (same function/module, same structural failure reason), implement, repeat. Batch edge cases
and validation variants together — don't waste a separate RED-GREEN cycle on each. Never batch
unrelated behaviors (vertical slices, not horizontal).

For context-isolated TDD, you **MUST** invoke the `tdd` skill (`/tdd`). Never dispatch `tdd-red` or
`tdd-green` agents directly — they exist solely for the `/tdd` orchestrator. Dispatching them
yourself bypasses phase verification, circuit breakers, and structured data passing.

**You are the coordinator, not the implementer.** Never write tests or implementation code yourself
— dispatch `tdd-red` and `tdd-green` via `/tdd`. Never read implementation source files to "prepare"
or "understand the API" — that's the RED agent's job. You describe _what behaviors to test_; agents
figure out _how_.

For quick single-context TDD (small bug fixes), follow RED-GREEN-REFACTOR directly: failing test,
minimal fix, verify pass, run full suite.

If an implementation attempt fails 3 times, try a different approach. After 5 total failures, stop
and report.

A test suite existing anywhere in the project qualifies — do not skip TDD because the specific
module or area being fixed has no tests yet. That's where you add them.

**Wrote fix code before the test?** Copy the modified files to a temp directory, restore the
originals from the backup, write the failing test, watch it fail, then copy the fixed files back. Do
not use git commands to revert — just file copies. The test must fail before the fix lands — that's
the proof it catches the bug.

### Pre-commit hooks use `prek`, not `pre-commit`

This user uses `prek` as the pre-commit hook runner. Never assume `.pre-commit-config.yaml` means
the `pre-commit` command exists. Always use `prek` for running hooks (e.g. `prek run -a`).

### No internal tooling leaks in user-facing output

Never expose internal tooling details in commits, PRs, code comments, or any output visible to
people outside this Claude session. This includes:

- **GSD IDs and planning references**: phase IDs (`01-01`, `phase-3`), plan IDs (`EXEC-04`),
  milestone labels, or any `.planning/` artifact names.
- **Skill names and invocations**: `/tdd`, `/preflight`, `code-py`, `tdd-red`, `tdd-green`,
  `code-distill`, `vet-code`, `vet-test`, or any skill/agent name.
- **Internal conventions**: references to "the orchestrator", "RED-GREEN cycle", "circuit breaker",
  subagent dispatch patterns, or any process that only exists within Claude's workflow.

Commit messages, PR descriptions, and code comments describe **what was built or fixed** — not the
tooling or process that produced it.

- **Bad**: `feat(01-02): implement CLI module`
- **Bad**: `fix: resolve bug found during /tdd RED phase`
- **Bad**: `# Added per vet-code recommendation`
- **Good**: `feat: implement CLI module and entrypoint`
- **Good**: `fix: reject empty email in form submission`
- **Good**: `# Validate email before processing`

### Load `write-plan` before creating any plan

Before using the Plan agent, EnterPlanMode, or writing a plan inline, **always** invoke
`Skill(write-plan)` first. This loads the plan format constraints (task structure, header, what
belongs in a plan vs. not). Without it, plans will use the wrong format.

### Plans describe behaviors, not TDD steps

When the project has a test suite, plan tasks describe **behaviors to implement** — not
implementation details. Never inline RED/GREEN steps, test assertions, or implementation code. Each
plan task ends with "Use `/tdd` for implementation." When the project has no test suite, plans
describe implementation directly (files, approach, specific changes).

### Load relevant skills in plans

When creating an implementation plan, always load the relevant language/tech skills as the first
step, before writing any code. Match skills to the languages and frameworks involved — e.g.
`code-py` and `test-py` for Python, `code-marimo` for Marimo notebooks, `code-lua` for Lua,
`code-shell` for shell scripts. This ensures coding standards and pitfall guards are active from the
start.

**Skills loaded during planning are NOT carried into implementation.** Plan mode context is erased
when the plan is approved. Always invoke skills again at the start of implementation, even if they
were loaded during planning. Never mark a skill as "already loaded".

If no matching skill exists for a language or framework, note that explicitly in the plan rather
than silently skipping the step.
