# Per-file reconcile rules (`update` mode)

How each config file is compared and merged during `update`. Apply after the leaf-path staging rules
in SKILL.md, using the same _add_ / _conflict_ / _removal candidate_ / project-owned classification.
Apply the chosen edits with `Edit`/`Write`, preserving comments and key order.

- `package.json` scope rules live in project-owned-keys.md; within `scripts`, reconcile both keys
  and values (same leaf-path rules as config files). Within `devDependencies`, reconcile only the
  key set — version ranges belong to `/upgrade-ts`.
- `.oxlintrc.json` `overrides` reconciles at the entry level: template rules inside an entry are
  house rules and must be present in the project entry matching the same glob; project-added
  entries, globs, and rules are owned (see project-owned-keys.md).
- `lefthook.yml` reconciles at the hook level: a hook name in the template but absent in the project
  is an _add_; a project-dropped hook is a _removal candidate_; project-added hooks are kept without
  surfacing as drift.
- `AGENTS.md` reconciles at the section level, not by leaf path: reconcile only the house sections
  `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, and
  `## Spelling (cspell)` against the template; leave every other section untouched and never surface
  it as drift (see project-owned-keys.md).
- The `.github/workflows/*.yml` files and `.github/dependabot.yml` are house-owned but routinely
  extended: ensure the template's jobs/steps are present, and keep project-added jobs, steps, and
  matrix entries without surfacing them as drift. If a template job differs, offer replace-or-keep
  for that entry.
- `.editorconfig` has no keys to merge — if it differs, offer replace-or-keep.
- `.gitignore` is line-based and additive: ensure the template's lines exist, and keep project-added
  lines without surfacing them as drift.
- `LICENSE` and the per-developer bootstrap files (`AGENTS.local.md`, `.mcp.json`) are project-owned
  once present — never reconciled.
