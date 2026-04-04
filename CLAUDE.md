# CLAUDE.md

## Rules

### Surface every issue — never skip silently

**Surface every issue — never skip silently.** When you find a bug, smell, or inconsistency: stop,
describe it, let the user decide (fix now, defer, or skip). Non-zero exit codes are errors — fix or
surface before anything else; never switch files or approaches to avoid one. Never attribute origin
("pre-existing", "not from this PR") — just diagnose and offer to fix.

### No destructive operations without explicit permission

Always ask before:

- **File deletion**: `rm`, `rm -rf`, `unlink`
- **Shell truncation**: `> file` or `echo "" > file`
- **Covert reverts**: reading git history (`git show`, `git cat-file`) then writing back via
  Write/Edit tools

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

When the project has a test suite, no production code before a failing test. A test suite anywhere
in the project qualifies. No test suite at all → skip TDD.

- **Bug or regression** (unknown root cause): use `/fix` — it investigates first, then drives TDD.
- **New feature** (root cause irrelevant): load `Skill(tdd)` directly and start the red–green cycle.

Never dispatch `tdd-red`/`tdd-green` directly.

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

### Skill loading

Always load the relevant skill before the corresponding action — every time, even if loaded earlier
in the same session. Plan mode context is erased on approval; never mark a skill as "already
loaded".

| Action                                    | Skill to load first                             |
| ----------------------------------------- | ----------------------------------------------- |
| EnterPlanMode or writing a plan           | `Skill(write-plan)`                             |
| Writing code                              | `Skill(code-*)` matching the language/framework |
| Writing tests                             | `Skill(test-*)` matching the language/framework |
| User explicitly asks to commit            | `Skill(write-commit)`                           |
| Bug or regression with unknown root cause | `/fix` command — investigates, then TDD         |
| New feature in a project with tests       | `Skill(tdd)` — start red–green cycle directly   |

If no matching skill exists for a language or framework, note that explicitly in the plan rather
than silently skipping the step.
