# CLAUDE.md

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
| "This is a pre-existing bug"                      | Now you've seen it. Surface it.                 |
| "I'll just work around it"                        | Workarounds hide problems. Surface it.          |
| "Let me use a different file/config/approach"     | That's a workaround. Fix the failing one first. |
| "That was already there / inherent / unavoidable" | Reworded deflection. Investigate alternatives.  |
| "My fix didn't cause this new issue"              | The user reported a problem. Fix it.            |

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

A test suite existing anywhere in the project qualifies — do not skip TDD because the specific
module or area being fixed has no tests yet. That's where you add them.

One behavior group at a time: write tests for a single concern or a cohesive batch of related
concerns (same function/module, same structural failure reason), implement, repeat. Batch edge cases
and validation variants together — don't waste a separate RED-GREEN cycle on each. Never batch
unrelated behaviors (vertical slices, not horizontal).

**Plan tasks describe behaviors to implement** — not implementation details. Never inline RED/GREEN
steps, test assertions, or implementation code in plans. Each plan task ends with "Use `/tdd` for
implementation." When the project has no test suite, plans describe implementation directly.

**Two modes:**

- **Quick (small bug fixes):** Follow RED-GREEN-REFACTOR directly in the main context: failing test,
  minimal fix, verify pass, run full suite.
- **Context-isolated (larger work):** Invoke the `tdd` skill (`/tdd`). Never dispatch `tdd-red` or
  `tdd-green` directly — they exist solely for the `/tdd` orchestrator. You describe _what behaviors
  to test_; agents figure out _how_. Never write tests or implementation code yourself, and never
  read implementation source files to "prepare".

If an implementation attempt fails 3 times, try a different approach. After 5 total failures, stop
and report.

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
- **Bad**: `chore: run preflight checks`
- **Bad**: `# Added per vet-code recommendation`
- **Good**: `feat: implement CLI module and entrypoint`
- **Good**: `fix: reject empty email in form submission`
- **Good**: `chore: fix lint and formatting issues`
- **Good**: `# Validate email before processing`

### Verify before claiming completion

Never claim tests pass, builds succeed, or work is complete without showing the command output that
proves it in the current message. "Should work" and "probably fixed" are not verification.

Before any success claim: identify the verification command, run it, read the full output, confirm
it supports the claim. Skip any step and the claim is unverified.

### Skill loading

Always load the relevant skill before the corresponding action — every time, even if loaded earlier
in the same session. Plan mode context is erased on approval; never mark a skill as "already
loaded".

| Action                          | Skill to load first                                                       |
| ------------------------------- | ------------------------------------------------------------------------- |
| `git commit` or staging files   | `write-commit`                                                            |
| EnterPlanMode or writing a plan | `write-plan`                                                              |
| Writing code                    | Load the matching `code-*` and `test-*` skills for the language/framework |

If no matching skill exists for a language or framework, note that explicitly in the plan rather
than silently skipping the step.

@RTK.md
