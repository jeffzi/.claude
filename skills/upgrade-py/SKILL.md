---
name: upgrade-py
description: Upgrades all Python dependencies with uv, re-pins pyproject.toml constraints to caret bounds, bumps remote prek hook revs, then runs prek and pytest.
# Quality floor: resolving post-upgrade prek/pytest breakage from major bumps needs more than the cheap tier.
model: sonnet
effort: medium
allowed-tools: >
  Read, Grep, Edit, Bash(uv sync:*),
  Bash(uv pip list:*), Bash(uv run prek:*),
  Bash(uv run pytest:*)
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
| Run prek checks                   | Running prek                 |
| Run tests                         | Running tests                |

If a conditional step is skipped (e.g., no changes needed), mark its task completed immediately.

## Pinning Strategy

Pin every explicit dependency with a **breaking-boundary caret**: cap at the next version semver
allows to break compatibility, floor one granularity finer.

- **major ≥ 1** — the breaking axis is the major. Cap at the next major; floor at the installed
  `major.minor`, dropping the patch: installed `2.12.5` → `>=2.12,<3`.
- **major 0** — the breaking axis is the minor (semver leaves 0.x pre-stable). Cap at the next
  minor; floor at the installed `0.minor.patch`, keeping the patch: installed `0.16.4` →
  `>=0.16.4,<0.17`.

The lockfile pins exact versions, so these ranges only bound how far an automated
`uv sync --upgrade` may move on its own. Crossing a boundary — a new major, or a new minor on a 0.x
tool — means widening the constraint by hand: a deliberate checkpoint to read the changelog. Tools
whose output gates CI (ruff, prek) get that review for free.

Dual-use tools — run both directly and as a prek hook — carry no separate version anywhere else.
They are `local` prek hooks invoking `uv run <tool>`, so the pyproject.toml constraint is their one
source. Only prek-only hooks keep a `rev` in `.pre-commit-config.yaml`; that rev is their single
source, bumped by `prek autoupdate` (step 5).

## Steps

1. Run `uv sync --upgrade --all-groups` to upgrade all dependencies

2. Find all dependencies explicitly mentioned in the pyproject.toml file. Use `uv pip list` to show
   the packages that are now installed.

3. Update dependency constraints in pyproject.toml based on `uv pip list`, applying the Pinning
   Strategy above (installed 2.12.5 → `>=2.12,<3`; installed 0.16.4 → `>=0.16.4,<0.17`). If
   constraints already match, skip to next step.

4. Run `uv sync --all-groups` again to ensure the updated constraints work (skip if no changes were
   made)

5. Run `uv run prek autoupdate` to upgrade the remote prek hook revs (markdownlint, cspell,
   actionlint, zizmor, ...). Dual-use tools (ruff, pyrefly, prek) are local hooks with no rev —
   their versions already moved via steps 1 and 3, so there is nothing to sync here.

6. Run `uv run prek run -a` and fix any issues (run again if files were modified)

7. Run `uv run pytest` to verify all tests still pass (if tests/ directory exists)

## Important Notes

- Preserve all comments in pyproject.toml
- Unless explicitly noted, DO NOT upgrade to pre-release or alpha versions. Upgrade only to stable
  versions.

## Files Included in Context

@pyproject.toml @.pre-commit-config.yaml
