# CLAUDE.md

## Rules

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

### TDD — mandatory, non-negotiable

When asked to fix a bug or implement a feature/behavior change and the project has a test suite, you
**MUST** follow TDD. Do NOT touch production code until a failing test proves the need. No
exceptions.

One behavior group at a time: write tests for a single concern or a cohesive batch of related
concerns (same function/module, same structural failure reason), implement, repeat. Batch edge cases
and validation variants together — don't waste a separate RED-GREEN cycle on each. Never batch
unrelated behaviors (vertical slices, not horizontal).

For context-isolated TDD, you **MUST** invoke the `tdd` skill (`/tdd`). Never dispatch `tdd-red` or
`tdd-green` agents directly — they exist solely for the `/tdd` orchestrator. Dispatching them
yourself bypasses phase verification, circuit breakers, and structured data passing.

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

**Rationalizations to block** — if you think any of these, STOP:

| Excuse                                  | Reality                                                               |
| --------------------------------------- | --------------------------------------------------------------------- |
| "The fix is obvious / trivial"          | Obvious fixes break obvious assumptions. Test first.                  |
| "I'll add a test after the fix"         | A test that never failed proves nothing. Test first.                  |
| "This is a one-liner"                   | One-liners still need proof they work. Test first.                    |
| "The bug is in code without tests"      | That's exactly where you add them. Test first.                        |
| "Let me just fix it quickly first"      | This is the exact failure mode this rule exists to prevent.           |
| "This is a new feature, not a bug fix"  | TDD applies to features too.                                          |
| "I need to see the whole picture first" | That's exploration. Delete it, start with TDD.                        |
| "Let me batch these together"           | Batch related concerns only. Unrelated behaviors get separate cycles. |

### Fix issues you encounter — don't deflect

When you discover an issue during work or the user asks about one after the main task, fix it
properly. No blame attribution. No scope gatekeeping. Don't deflect blame, apply workarounds, then
declare it "out of scope." Go straight to root cause.

**Rationalizations to block** — if you think any of these, STOP:

| Excuse                                            | Reality                                         |
| ------------------------------------------------- | ----------------------------------------------- |
| "This isn't from my changes"                      | Irrelevant. You found it, you fix it.           |
| "This is a pre-existing issue"                    | Now it's your issue. Fix it properly.           |
| "This is outside the scope"                       | The user is asking you. That makes it in scope. |
| "Let me add a quick workaround"                   | Investigate the root cause. Do the proper fix.  |
| "Let me revert and leave it as-is"                | Don't give up. Iterate toward the real fix.     |
| "That was already there / inherent / unavoidable" | Reworded deflection. Investigate alternatives.  |
| "My fix didn't cause this new issue"              | The user reported a problem. Fix it.            |

### Plans describe behaviors, not TDD steps

Plan tasks describe **what to build** (behaviors, files, approach), not **how to TDD it**. Never
inline RED/GREEN steps, test assertions, or implementation code in a plan. Each plan task ends with
"Use `/tdd` for implementation."

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

### Superpowers plugin is disabled

The `superpowers@superpowers-marketplace` plugin is disabled. All workflow skills are local forks in
`~/.claude/skills/` (`using-skills`, `verification-before-completion`, `systematic-debugging`).
Never use `superpowers:*` skills — use the local equivalents instead.
