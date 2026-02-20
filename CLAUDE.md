# CLAUDE.md

## Rules

### No destructive operations without explicit permission

Never run any command that could destroy, overwrite, or discard uncommitted work. Always ask the
user first and explain why. This includes but is not limited to:

- **Git**: `checkout --`, `reset` (all forms including `reset HEAD`), `clean`, `stash`, `restore`
  (without `--staged`), `push --force`, `rebase` (with uncommitted changes), `branch -D`,
  `commit --amend`, or `--no-verify`. To unstage files, use `git restore --staged <path>` instead of
  `git reset`.
- **File deletion**: `rm`, `rm -rf`, `unlink`, or any command that removes files.
- **File overwriting**: Reading content from git history (`git show`, `git cat-file`) and writing it
  back via Write/Edit tools to revert a file.
- **Shell redirects**: Truncating files via `> file` or `echo "" > file`.

### TDD for bug fixes

When asked to fix a bug and the project has existing tests:

1. **Write a failing test first** that reproduces the bug.
2. **Run the test** to confirm it fails for the expected reason.
3. **Fix the bug** with the minimal change needed.
4. **Run the test again** to confirm it passes.
5. **Run the full test suite** to ensure no regressions.

Never skip straight to the fix. The failing test is the proof the bug exists and the proof it's
resolved.

A test suite existing anywhere in the project qualifies — do not skip TDD because the specific
module or area being fixed has no tests yet. That's where you add them.

### Load relevant skills in plans

When creating an implementation plan, always load the relevant language/tech skills as the first
step, before writing any code. Match skills to the languages and frameworks involved — e.g.
`code-py` and `test-py` for Python, `code-marimo` for Marimo notebooks, `code-lua` for Lua,
`code-shell` for shell scripts. This ensures coding standards and pitfall guards are active from the
start.

**Important:** Skills loaded during planning are NOT carried into implementation — plan mode context
is erased when the plan is approved. Always invoke skills again at the start of implementation, even
if they were loaded during planning. Never mark a skill as "already loaded".

If no matching skill exists for a language or framework, note that explicitly in the plan rather
than silently skipping the step.

### Use prek for linting, run tests separately

Use [prek](https://github.com/j178/prek) (a fast Rust-based drop-in replacement for pre-commit). Run
`prek install` to set up hooks, never `pre-commit`.

For linting and formatting, always use `uv tool run prek run -a` (all files) over invoking
individual tools (ruff, basedpyright, dprint, etc.) directly. Prek already orchestrates them with
the right config. Only fall back to individual commands when debugging a specific linter issue.

Tests are **not** part of pre-commit hooks and must always be run separately (e.g. `uv run pytest`).
Plans should include distinct steps: one for linting via `uv tool run prek run -a`, another for
running tests.

Always prefix project tool commands with `uv run` (e.g. `uv run pytest`, `uv run ruff`). For prek,
use `uv tool run prek` since it's an external tool, not a project dependency.
