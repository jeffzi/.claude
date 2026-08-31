# Per-file reconcile rules (`update` mode)

How each config file is compared and merged during `update`. Apply after the leaf-path staging rules
in SKILL.md, using the same _add_ / _conflict_ / _removal candidate_ / project-owned classification.
Apply the chosen edits with `Edit`/`Write`, preserving comments and key order.

- `pyproject.toml` is TOML: reconcile the `[tool.ruff]`, `[tool.pyrefly]`,
  `[tool.pytest.ini_options]`, `[tool.coverage]`, `[tool.uv]`, and `[build-system]` tables with the
  leaf-path rules; `[project]` and the `dev` group's version ranges are project-owned (see
  project-owned-keys.md), and within `[dependency-groups] dev` reconcile only the key set.
- `.pre-commit-config.yaml` reconciles at the hook level: a `repo`/`id` in the template but absent
  in the project is an _add_; a project-dropped hook is a _removal candidate_; `rev` values are
  never a conflict — they belong to `/upgrade-py`.
- `AGENTS.md` reconciles at the section level, not by leaf path: reconcile only the house sections
  `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, and
  `## Spelling (cspell)` against the template; leave every other section untouched and never surface
  it as drift (see project-owned-keys.md).
- `Taskfile.yml` and the `.github/workflows/*.yml` files are house-owned but routinely extended:
  ensure the template's tasks/jobs/steps are present, and keep project-added tasks, jobs, matrix
  entries, and steps without surfacing them as drift. If a template task/job differs, offer
  replace-or-keep for that entry.
- `scripts/check_max_lines.py` is house-owned code, not config — if it differs from the template,
  offer replace-or-keep for the whole file; never merge line-by-line.
- `.editorconfig` has no keys to merge — if it differs, offer replace-or-keep.
- `.gitignore` is line-based and additive: ensure the template's lines exist, and keep project-added
  lines without surfacing them as drift.
- `LICENSE`, `README.md`, and the per-developer bootstrap files are project-owned once present —
  never reconciled.
