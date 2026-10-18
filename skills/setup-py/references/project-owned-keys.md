# Project-Owned Keys

Keys the template ships with a default value but the project may freely override. Exclude from every
reconcile bucket — read them (so they aren't miscounted as removals) but keep their value as-is.
Never surface as drift.

| File                       | Owned keys                                                                                                                                                                                                              |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pyproject.toml`           | All of `[project]`, `[project.scripts]`, `[project.urls]`, `[project.optional-dependencies]`                                                                                                                            |
| `pyproject.toml`           | `requires-python`, `[tool.pyrefly] python-version`                                                                                                                                                                      |
| `pyproject.toml`           | `[tool.coverage.report] fail_under` (project may raise the floor)                                                                                                                                                       |
| `pyproject.toml`           | `[tool.pytest.ini_options] faulthandler_timeout` (tuned to the project's slowest test)                                                                                                                                  |
| `pyproject.toml`           | project-added `[tool.ruff.lint] per-file-ignores` globs and codes, `allowed-confusables`                                                                                                                                |
| `pyproject.toml`           | project-added `[tool.pytest.ini_options] asyncio_mode` (async test suites)                                                                                                                                              |
| `.pre-commit-config.yaml`  | every `rev:` value (upgrade-py owns hook pins)                                                                                                                                                                          |
| `.pre-commit-config.yaml`  | project-added hooks (a `repo: local` drift check, a generator)                                                                                                                                                          |
| `.markdownlint-cli2.jsonc` | project-added rule entries                                                                                                                                                                                              |
| `cspell.json`              | `words`, project-added `ignorePaths` entries                                                                                                                                                                            |
| `dprint.json`              | `excludes`, project-added `includes` entries                                                                                                                                                                            |
| `AGENTS.md`                | Every section except `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, `## Module layout`, `## Docstrings`, `## Spelling (cspell)`; the `### Project facts` values inside `## Module layout` |
| `Taskfile.yml`             | project-added tasks                                                                                                                                                                                                     |
| `.github/workflows/*.yml`  | project-added jobs, steps, and matrix entries                                                                                                                                                                           |
| `LICENSE`, `README.md`     | entirely project-owned once present (bootstrap-only, never reconciled)                                                                                                                                                  |

`pyproject.toml` `[project]` is entirely project-owned (name, version, description, `dependencies`,
readme). The Python version keys (`requires-python`, pyrefly `python-version`) travel with the
project's chosen floor — reconcile only that they are present, never their value. Ruff infers its
`target-version` from `requires-python`, so the template does not set it; a project that does is
surfaced like any other project-added key.

`[dependency-groups] dev` is owned like TypeScript's `devDependencies`: reconcile the **key set**
(which tools are present) but leave version ranges to `/upgrade-py`. A tool the template ships that
the project dropped is a removal candidate; a tool the project added is owned. Optional extras need
no `dev` entry: every sync (Taskfile, CI) runs `uv sync --locked --all-extras`, so the lockfile
installs them all.

`[tool.ruff]`, `[tool.pyrefly]`, `[tool.pymaxlines]`, `[tool.pytest.ini_options]`,
`[tool.coverage]`, `[tool.uv]` bodies (other than the owned keys above), `[build-system]`, and the
whole `.pre-commit-config.yaml` hook set are house rules — reconcile with the normal
add/conflict/removal logic. `[tool.uv] exclude-newer` is a house supply-chain control: treat it as a
house rule so projects seeded before it existed receive it on `update`.

`Taskfile.yml` and the `.github/workflows/*.yml` files are house-owned but additive: the template's
tasks/jobs/steps are house rules (ensure they are present), while tasks, jobs, matrix entries, and
steps the project adds are owned — keep them without surfacing as drift, the same way project-added
`.gitignore` lines are kept.

`.pre-commit-config.yaml` reconciles at the hook level: a `repo`/`id` present in the template but
absent in the project is an _add_; a hook the project dropped is a _removal candidate_; a hook the
project added is owned — keep it without surfacing as drift; `rev` values are never a conflict (they
belong to `/upgrade-py`).
