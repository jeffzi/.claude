---
name: upgrade-py
description: Use when upgrading Python dependencies in lock file and pyproject.toml
allowed-tools: >
  Read, Grep, Edit, Bash(uv sync:*),
  Bash(uv pip list:*), Bash(uv tool run prek:*),
  Bash(uv run pytest:*)
---

# Upgrade All Python Dependencies

Upgrade all project dependencies while keeping pyproject.toml constraints in sync.

## Task Tracking

**Create task list at start** using TaskCreate for progress tracking:

| Task subject                      | activeForm (spinner text)    |
| --------------------------------- | ---------------------------- |
| Upgrade lock file                 | Upgrading dependencies       |
| Update pyproject.toml constraints | Updating version constraints |
| Upgrade prek hooks                | Upgrading prek hooks         |
| Sync pinned versions              | Syncing pinned versions      |
| Run prek checks                   | Running prek                 |
| Run tests                         | Running tests                |

Update tasks with TaskUpdate as you progress:

- Set `status: in_progress` when starting each phase (shows spinner with activeForm text)
- Set `status: completed` when done (shows checkmark)
- If a conditional step is skipped (e.g., no changes needed), mark it completed immediately

## Pinning Strategy

- **Caret** (`>=MAJOR.MINOR,<NEXT_MAJOR`) — default for dependencies with major >= 1. Lower bound is
  the installed major.minor (drop the patch). Trusts semver; allows any version within the same
  major.
- **Floor** (`>=X.Y.Z`) — for 0.x dependencies (no upper bound). Semver treats 0.x as unstable, so
  just pin the floor to the latest installed version.
- **Exact** (`==X.Y.Z`) — only for tools shared with prek (e.g., ruff, sqlfluff). The hook pins an
  exact rev, so the pyproject.toml pin must match to keep behavior identical whether the tool runs
  directly or via prek.

## Steps

1. Run `uv sync --upgrade --all-groups` to upgrade all dependencies

2. Find all dependencies explicitly mentioned in the pyproject.toml file. Use `uv pip list` to show
   the packages that are now installed.

3. Update non-exact dependencies in pyproject.toml based on `uv pip list`. For major >= 1, use
   caret: `>=MAJOR.MINOR,<NEXT_MAJOR` — drop the patch (e.g., installed 2.12.5 → `>=2.12,<3`). For
   0.x, use the exact installed version as floor: `>=INSTALLED` (e.g., 0.29.0 → `>=0.29.0`). Skip
   `==` pins — those are synced from prek in step 6. If constraints already match, skip to next
   step.

4. Run `uv sync --all-groups` again to ensure the updated constraints work (skip if no changes were
   made)

5. Run `uv tool run prek autoupdate` to upgrade prek hook versions

6. Update pinned versions in pyproject.toml to match .pre-commit-config.yaml (ruff and sqlfluff must
   be kept in sync between both files). If versions already match, skip to next step.

7. Run `uv sync --all-groups` again to install the updated pinned versions (skip if no changes were
   made)

8. Run `uv tool run prek run -a` and fix any issues (run again if files were modified)

9. Run `uv run pytest` to verify all tests still pass (if tests/ directory exists)

## Important Notes

- Exact-pinned (`==`) tools must match between pyproject.toml and .pre-commit-config.yaml. The flow
  is: prek autoupdate bumps the hook rev → you update the `==` pin in pyproject.toml to match
- Preserve all comments in pyproject.toml
- Unless explicitly noted, DO NOT upgrade to pre-release or alpha versions. Upgrade only to stable
  versions.

## Files Included in Context

@pyproject.toml @.pre-commit-config.yaml
