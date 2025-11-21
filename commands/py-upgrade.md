---
description: Upgrade Python dependencies in lock file and pyproject.toml
allowed-tools: Read, Grep, Edit, Bash(uv sync:*), Bash(uv pip list:*), Bash(uv run pre-commit:*), Bash(uv run pytest:*)
---

# Upgrade All Python Dependencies

Upgrade all project dependencies while keeping pyproject.toml constraints in sync.

## Steps

1. Run `uv sync --upgrade --all-groups` to upgrade all dependencies

2. Find all dependencies explicitly mentioned in the pyproject.toml file. Use `uv pip list` to show the packages that are now installed.

3. Update the minimum version constraints in pyproject.toml to match the exact versions from the `uv pip list` output (e.g., change `>=2,<3` to `>=2.4.0,<3` if lockfile shows 2.4.0). If versions already match, skip to next step.

4. Run `uv sync --all-groups` again to ensure the updated constraints work (skip if no changes were made)

5. Run `uv run pre-commit autoupdate` to upgrade pre-commit hook versions

6. Update pinned versions in pyproject.toml to match .pre-commit-config.yaml (ruff and sqlfluff must be kept in sync between both files). If versions already match, skip to next step.

7. Run `uv sync --all-groups` again to install the updated pinned versions (skip if no changes were made)

8. Run `uv run pre-commit run -a` and fix any issues (run again if files were modified)

9. Run `uv run pytest` to verify all tests still pass (if tests/ directory exists)

## Important Notes

- Pinned versions (with `==` like ruff and sqlfluff) must be kept in sync between pyproject.toml and .pre-commit-config.yaml - update both files when pre-commit autoupdate changes them
- Preserve all comments in pyproject.toml
- Unless explicitly noted, DO NOT upgrade to pre-release or alpha versions. Upgrade only to stable versions.

## Files Included in Context

@pyproject.toml
@.pre-commit-config.yaml
