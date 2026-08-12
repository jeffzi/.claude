---
name: upgrade-py
description: Upgrades all Python dependencies with uv, syncs pyproject.toml constraints and prek hook pins, then runs prek and pytest.
# Quality floor: resolving post-upgrade prek/pytest breakage from major bumps needs more than the cheap tier.
model: sonnet
effort: medium
allowed-tools: >
  Read, Grep, Edit, Bash(uv sync:*),
  Bash(uv pip list:*), Bash(uv tool run prek:*),
  Bash(uv run pytest:*)
disable-model-invocation: true
---

# Upgrade All Python Dependencies

Upgrade all project dependencies while keeping pyproject.toml constraints in sync.

## Context

- Outdated packages:
  !`uv pip list --outdated 2>/dev/null || echo "(uv not available or no outdated packages)"`

## Task Tracking

**Create task list at start** using TaskCreate for progress tracking:

| Task subject                      | activeForm (spinner text)    |
| --------------------------------- | ---------------------------- |
| Upgrade lock file                 | Upgrading dependencies       |
| Update pyproject.toml constraints | Updating version constraints |
| Upgrade prek hooks                | Upgrading prek hooks         |
| Sync exact pins                   | Syncing exact pins           |
| Run prek checks                   | Running prek                 |
| Run tests                         | Running tests                |

If a conditional step is skipped (e.g., no changes needed), mark its task completed immediately.

## Pinning Strategy

- **Caret** (`>=MAJOR.MINOR,<NEXT_MAJOR`) — default for dependencies with major >= 1. Lower bound is
  the installed major.minor (drop the patch). Trusts semver; allows any version within the same
  major.
- **Floor** (`>=X.Y.Z`) — for 0.x dependencies (no upper bound). Semver treats 0.x as unstable, so
  just pin the floor to the latest installed version.
- **Exact** (`==X.Y.Z`) — only for tools shared with prek (e.g., ruff). The hook pins an exact rev,
  so the pyproject.toml pin must match to keep behavior identical whether the tool runs directly or
  via prek.

## Steps

1. Run `uv sync --upgrade --all-groups` to upgrade all dependencies

2. Find all dependencies explicitly mentioned in the pyproject.toml file. Use `uv pip list` to show
   the packages that are now installed.

3. Update non-exact dependencies in pyproject.toml based on `uv pip list`, applying the Pinning
   Strategy above (e.g., installed 2.12.5 → `>=2.12,<3`; installed 0.29.0 → `>=0.29.0`). Skip exact
   pins — those are synced from prek in step 6. If constraints already match, skip to next step.

4. Run `uv sync --all-groups` again to ensure the updated constraints work (skip if no changes were
   made)

5. Run `uv tool run prek autoupdate` to upgrade prek hook versions

6. Update exact (`==`) pins in pyproject.toml to match prek hook revs in .pre-commit-config.yaml. If
   versions already match, skip to next step.

7. Run `uv sync --all-groups` again to install the updated exact pins (skip if no changes were made)

8. Run `uv tool run prek run -a` and fix any issues (run again if files were modified)

9. Run `uv run pytest` to verify all tests still pass (if tests/ directory exists)

## Important Notes

- Preserve all comments in pyproject.toml
- Unless explicitly noted, DO NOT upgrade to pre-release or alpha versions. Upgrade only to stable
  versions.

## Files Included in Context

@pyproject.toml @.pre-commit-config.yaml
