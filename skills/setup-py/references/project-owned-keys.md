# Project-Owned Keys

Keys the template ships with a default value but the project may freely override. Exclude from every
reconcile bucket — read them (so they aren't miscounted as removals) but keep their value as-is.
Never surface as drift.

| File                       | Owned keys                                                                                   |
| -------------------------- | -------------------------------------------------------------------------------------------- |
| `pyproject.toml`           | All of `[project]`, `[project.scripts]`, `[project.urls]`, `[project.optional-dependencies]` |
| `pyproject.toml`           | `requires-python`, `[tool.ruff] target-version`, `[tool.pyrefly] python-version`             |
| `pyproject.toml`           | `[tool.coverage.report] fail_under` (project may raise the floor)                            |
| `.pre-commit-config.yaml`  | every `rev:` value (upgrade-py owns hook pins)                                               |
| `.markdownlint-cli2.jsonc` | project-added rule entries                                                                   |
| `cspell.json`              | `words`, project-added `ignorePaths` entries                                                 |
| `dprint.json`              | `excludes`, project-added `includes` entries                                                 |
| `AGENTS.md`                | Every section except `## Commands`, `## Git hygiene`, `## Anti-patterns`                     |
| `Taskfile.yml`             | project-added tasks                                                                          |
| `.github/workflows/*.yml`  | project-added jobs, steps, and matrix entries                                                |
| `LICENSE`, `README.md`     | entirely project-owned once present (bootstrap-only, never reconciled)                       |

`pyproject.toml` `[project]` is entirely project-owned (name, version, description, `dependencies`,
readme). The Python version keys (`requires-python`, Ruff `target-version`, pyrefly
`python-version`) travel with the project's chosen floor — reconcile only that they are present,
never their value.

`[dependency-groups] dev` is owned like TypeScript's `devDependencies`: reconcile the **key set**
(which tools are present) but leave version ranges to `/upgrade-py`. A tool the template ships that
the project dropped is a removal candidate; a tool the project added is owned.

`[tool.ruff]`, `[tool.pyrefly]`, `[tool.pytest.ini_options]`, `[tool.coverage]`, `[tool.uv]` bodies
(other than the owned keys above), `[build-system]`, and the whole `.pre-commit-config.yaml` hook
set are house rules — reconcile with the normal add/conflict/removal logic.
`[tool.uv] exclude-newer` is a house supply-chain control: treat it as a house rule so projects
seeded before it existed receive it on `update`.

`Taskfile.yml` and the `.github/workflows/*.yml` files are house-owned but additive: the template's
tasks/jobs/steps are house rules (ensure they are present), while tasks, jobs, matrix entries, and
steps the project adds are owned — keep them without surfacing as drift, the same way project-added
`.gitignore` lines are kept.

`.pre-commit-config.yaml` reconciles at the hook level: a `repo`/`id` present in the template but
absent in the project is an _add_; a hook the project dropped is a _removal candidate_; `rev` values
are never a conflict (they belong to `/upgrade-py`).
