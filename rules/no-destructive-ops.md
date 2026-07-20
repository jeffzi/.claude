# No Destructive Operations Without Explicit Permission

Never run any command that could destroy, overwrite, or discard uncommitted work. Always ask the
user first and explain why. This includes but is not limited to:

- **Git (discarding changes)**: `checkout` (all forms — use `git switch` for branches,
  `git restore
  --staged` for unstaging), `switch -f`/`--force`/`--discard-changes`, `restore`
  (without `--staged`), `reset` (all forms including `reset HEAD`), `clean`, `stash`,
  `apply -R`/`--reverse`. To unstage files, use `git restore --staged <path>` instead of
  `git reset`.
- **Git (rewriting history / bypassing safeguards)**: `commit --amend`, `push --force`, `rebase`
  (with uncommitted changes), `branch -D`, `--no-verify` on any command.
- **Git (tracking ignored files)**: `add -f`/`--force` on gitignored files. Never force-add files
  that match a local or global gitignore rule.
- **File overwriting**: Reading content from git history (`git show`, `git cat-file`) and writing it
  back via Write/Edit tools or shell redirects (`git show HEAD:file > file`) to revert a file.
- **File deletion**: `rm`, `rm -rf`, `unlink`, or any command that removes files.
- **Shell redirects**: Truncating project files via `> file` or `echo "" > file` — scratch/temp
  capture files (`/tmp/*`, scratchpad) are exempt.
- **Worktrees**: `git worktree remove` or `ExitWorktree` when the worktree has uncommitted changes.
  Always commit work before leaving a worktree.
