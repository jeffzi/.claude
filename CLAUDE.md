# CLAUDE.md

## Rules

### No destructive operations without explicit permission

Never run any command that could destroy, overwrite, or discard uncommitted work. Always ask the
user first and explain why. This includes but is not limited to:

- **Git**: `checkout --`, `reset --hard`, `clean`, `stash`, `restore` (without `--staged`), or any
  flag/command that bypasses git's safety checks.
- **File deletion**: `rm`, `rm -rf`, `unlink`, or any command that removes files.
- **File overwriting**: Reading content from git history (`git show`, `git cat-file`) and writing it
  back via Write/Edit tools to revert a file.
- **Shell redirects**: Truncating files via `> file` or `echo "" > file`.

### Use prek, not pre-commit

Use [prek](https://github.com/j178/prek) (a fast Rust-based drop-in replacement) instead of
pre-commit. Run `prek install` and `prek run`, never `pre-commit`.
