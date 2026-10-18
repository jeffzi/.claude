# Per-file reconcile rules (`update` mode)

How each config file is compared and merged during `update`. Apply after the leaf-path staging rules
in SKILL.md, using the same _add_ / _conflict_ / _removal candidate_ / project-owned classification.
Apply the chosen edits with `Edit`/`Write`, preserving comments and key order. For owned keys in
each file, see `project-owned-keys.md`.

- `Cargo.toml` is TOML: reconcile the `[lints.rust]` and `[lints.clippy]` tables with the leaf-path
  rules. Owned keys per `project-owned-keys.md`.
- `rust-toolchain.toml` reconciles `components` and `profile` as house rules.
- `rustfmt.toml` reconciles all keys as house rules (small file, few keys).
- `deny.toml` reconciles `[licenses] allow`, `[bans] multiple-versions`, `[sources]` keys as house
  rules. Owned keys per `project-owned-keys.md`.
- `.pre-commit-config.yaml` reconciles at the hook level: a `repo`/`id` in the template but absent
  in the project is an _add_; a project-dropped hook is a _removal candidate_. Owned keys per
  `project-owned-keys.md`.
- `AGENTS.md` reconciles at the section level, not by leaf path: reconcile only the house sections
  `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, `## Doc comments`,
  and `## Spelling (cspell)` against the template; leave every other section untouched and never
  surface it as drift.
- `Taskfile.yml` and the `.github/workflows/*.yml` files are house-owned but routinely extended:
  ensure the template's tasks/jobs/steps are present. If a template task/job differs, offer
  replace-or-keep for that entry. Owned keys per `project-owned-keys.md`.
- `dprint.json` is JSON: reconcile `lineWidth`, `markdown`, and `plugins` with the leaf-path rules.
  Project-added `includes` entries and `excludes` are owned.
- `.markdownlint-cli2.jsonc` is JSONC: reconcile `config` rules with the leaf-path rules.
  Project-added rule entries are owned.
- `.editorconfig` has no keys to merge -- if it differs, offer replace-or-keep.
- `.gitignore` is line-based and additive: ensure the template's lines exist, and keep project-added
  lines without surfacing them as drift.
- `.github/dependabot.yml` is house-owned: ensure the template's ecosystem entries are present, and
  keep project-added entries without surfacing them as drift.
- `LICENSE` is project-owned once present -- never reconciled.
