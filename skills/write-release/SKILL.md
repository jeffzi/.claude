---
name: write-release
description: >
  Use when tagging a release, bumping a version, or publishing a GitHub release.
  Use when unsure which version to bump or what files need updates.
  Not for changelog-only edits — use write-changelog.
  Not for commit messages — use write-commit.
argument-hint: "[version | patch | minor | major] [--gh-release]"
allowed-tools: Read, Edit, Grep, Glob, Bash(grep *), Bash(git *), Bash(gh *), Bash(npm *), Bash(pnpm *), Bash(yarn *), Bash(uv *), Bash(poetry *), Bash(cargo *), Bash(bundle *)
---

# Release

Bump versions everywhere, refresh lock files, update the changelog, commit, and tag — one release,
one commit.

## Context

- Last tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "(no tags)"`
- Commits since last tag:
  !`git log $(git describe --tags --abbrev=0 2>/dev/null)..HEAD --oneline 2>/dev/null \
  || git log --oneline -20`
- Existing tag format: !`git tag --sort=-creatordate 2>/dev/null | head -5`

## Version Resolution

`$ARGUMENTS` determines the target version and optional flags:

| Argument                | Action                                                |
| ----------------------- | ----------------------------------------------------- |
| `1.2.3` or `v1.2.3`     | Use as-is (strip `v` for files, keep for tag)         |
| `patch` `minor` `major` | Bump that segment from current version                |
| _(none)_                | Analyze commits since last tag, suggest bump, confirm |
| `--gh-release`          | Also create a GitHub release after tagging            |

### Suggesting a bump

When no version is given, scan commits since the last tag using Conventional Commits:

| Signal                                          | Bump                                |
| ----------------------------------------------- | ----------------------------------- |
| Any `BREAKING CHANGE:` footer or `!` after type | **major** (or **minor** if < 1.0.0) |
| Any `feat` type                                 | **minor** (or **patch** if < 1.0.0) |
| Only `fix`, `perf`, `refactor`, `chore`, etc.   | **patch**                           |

Present the suggestion with the commit evidence. Confirm before proceeding.

## Release Flow

### 0. Check working tree

The release commit must contain only release edits. Before anything else, check for uncommitted
work:

```bash
git status --short
```

If the tree is dirty, show the output and ask the user what to do — commit first, or abort. Do not
proceed with a dirty tree.

### 1. Discover current version

Read the primary version file. Then search for the version string across the project to find every
file that needs bumping:

```bash
grep -rn "CURRENT_VERSION" --include='*.json' --include='*.toml' --include='*.cfg' \
  --include='*.py' --include='*.rb' --include='*.gemspec' --include='*.rs' .
```

Present all findings. Confirm the bump list with the user before editing.

### 2. Resolve target version

Apply version resolution rules. If no argument was given, suggest a bump level with commit evidence.
Confirm the target version with the user.

### 3. Bump version in all files

Edit every version-bearing file found in step 1. Do **not** hand-edit lock files — step 4 handles
them.

### 4. Refresh lock files

Run the ecosystem's lock command. **This is not optional.** A version bump without a lock file
refresh ships a broken install.

| Ecosystem       | Lock file           | Refresh command                   |
| --------------- | ------------------- | --------------------------------- |
| Node (npm)      | `package-lock.json` | `npm install --package-lock-only` |
| Node (pnpm)     | `pnpm-lock.yaml`    | `pnpm install --lockfile-only`    |
| Node (yarn)     | `yarn.lock`         | `yarn install`                    |
| Python (uv)     | `uv.lock`           | `uv lock`                         |
| Python (poetry) | `poetry.lock`       | `poetry lock`                     |
| Rust            | `Cargo.lock`        | `cargo check`                     |
| Ruby            | `Gemfile.lock`      | `bundle install`                  |
| Go              | `go.sum`            | `go mod tidy`                     |

If no lock file exists, skip. If the refresh command needs tool approval, surface it — never skip
silently.

### 5. Update changelog

If `CHANGELOG.md` exists:

1. Load `Skill(write-changelog)`.
2. Move `[Unreleased]` entries to a new `## [X.Y.Z] - YYYY-MM-DD` section.
3. Reset `[Unreleased]` to empty with its type headings cleared.
4. Update comparison links at the bottom.

If no `CHANGELOG.md` exists, ask the user whether to create one.

### 6. Verify

Run the project's test suite, linter, and type checker **after** the version bump. All must pass
before proceeding. A release tagged on broken code is not a release.

### 7. Commit

Load `Skill(write-commit)` for message rules. The release commit bundles everything — version bumps,
lock file changes, and changelog — into one commit.

Subject: `chore: release vX.Y.Z` — no body needed, the changelog has the details.

This is a workflow-prescribed commit: write-commit's interactive confirmation flow does not apply.
Confirm the staged file list with the user before committing.

### 8. Tag

Annotated tag, always:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
```

- **`v` prefix** unless the project's existing tags use a different convention — match it.
- **Always annotated** (`-a`). Lightweight tags lose tagger, date, and message.
- Verify immediately:

```bash
git log --oneline -1 HEAD
git tag -v vX.Y.Z 2>/dev/null || git show -s --format='%H' vX.Y.Z
```

The tag must point at the release commit.

### 9. GitHub release (only with `--gh-release`)

Skip this step unless `$ARGUMENTS` contains `--gh-release`.

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes "$(awk '/^## \[X\.Y\.Z\]/{f=1;next} f && /^(## \[|\[.*\]: )/{exit} f' CHANGELOG.md)"
```

Extract the changelog section for this version as the release body. The `awk` stops at the next
version heading or at reference links — safe even for the first release. If no changelog, use
`--generate-notes`.

## Version Discovery Reference

Common version-bearing files by ecosystem:

| Ecosystem        | Version files                                  |
| ---------------- | ---------------------------------------------- |
| Node             | `package.json`                                 |
| Python (PEP 621) | `pyproject.toml` (`[project]` → `version`)     |
| Python (legacy)  | `setup.cfg`, `setup.py`                        |
| Python (runtime) | `__init__.py` or `_version.py` (`__version__`) |
| Rust             | `Cargo.toml` (`[package]` → `version`)         |
| Ruby             | `*.gemspec`, `lib/**/version.rb`               |
| Go               | — (tags are the version)                       |
| Generic          | `VERSION`, `.version`                          |

**Do not assume one file is enough.** A Python project may have the version in `pyproject.toml` AND
`__init__.py`. A Node project may have it in `package.json` AND a `version.ts` constant. Search.

## Common Mistakes

| Mistake                                             | Reality                                                              |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| "Lock file will update on next install"             | Next install is someone else's machine. Ship it correct.             |
| "Only package.json needs bumping"                   | `grep` for the version — it's in more files than you think.          |
| "Lightweight tag is fine"                           | Loses tagger, date, message. Always annotated.                       |
| "Working tree is clean enough"                      | Uncommitted work gets swept into the release commit. Check first.    |
| "I'll write the changelog later"                    | The release commit includes the changelog. Later never comes.        |
| "Tests passed before the bump"                      | Before is not after. Run them after the version bump.                |
| "Split version bump and changelog into two commits" | One release, one commit. Splitting fragments the history.            |
| "The project has no lock file, skip refresh"        | Correct — but verify the lock file truly doesn't exist, don't guess. |
| Using `release:` as the commit type                 | `release` is not a valid CC type. Use `chore: release vX.Y.Z`.       |
| Listing changes in the commit body                  | The changelog has the details. The commit body adds nothing.         |

## Red Flags — Stop and Reassess

- About to create a lightweight tag (`git tag X` without `-a`)
- About to proceed with a dirty working tree
- About to commit without running tests after the version bump
- Lock file exists but wasn't refreshed
- Version string found in a file that wasn't bumped
- Creating multiple commits for one release
- Skipping changelog update when `CHANGELOG.md` exists
