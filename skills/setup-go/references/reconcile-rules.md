# Per-file reconcile rules (`update` mode)

How each config file is compared and merged during `update`. Apply after the leaf-path staging rules
in SKILL.md, using the same _add_ / _conflict_ / _removal candidate_ / project-owned classification.
Apply the chosen edits with `Edit`/`Write`, preserving comments and key order. For owned keys in
each file, see `project-owned-keys.md`.

- `go.mod` reconciles the `tool` directive set (house tools present/absent) and `go`/`toolchain`
  directive presence. The `module` path, `require` block, and version values are project-owned.
- `.golangci.yml` is YAML: reconcile `version`, `formatters.enable`, `linters.enable`,
  `linters.exclusions.rules`, and house-owned `linters.settings` keys with the leaf-path rules.
  Project-added settings are owned.
- `.golangci.tests.yml` is the second golangci-lint config, holding only the file cap for `_test.go`
  files: reconcile it with the leaf-path rules. Its `max` is a project fact — see the `AGENTS.md`
  entry below.
- `.coverage.yml` holds the coverage floor: reconcile `profile` with the leaf-path rules. The
  `threshold` values are project-owned.
- `.pre-commit-config.yaml` reconciles at the hook level: a `repo`/`id` in the template but absent
  in the project is an _add_; a project-dropped hook is a _removal candidate_. `rev` values are
  never a conflict — they belong to update-tools.
- `AGENTS.md` reconciles at the section level, not by leaf path: reconcile only the house sections
  `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, `## Project layout`,
  `## Package and file layout`, `## Doc comments`, and `## Spelling (cspell)` against the template;
  leave every other section untouched and never surface it as drift.
  - Within `## Package and file layout`, the `### Project facts` subsection is project-owned:
    reconcile only that it is present, never its values. Its caps must match the lint config: the
    `funlen` settings and the `file-length-limit` `max` in `.golangci.yml` and
    `.golangci.tests.yml`. Surface a mismatch between the facts and the config as a conflict.
- `Taskfile.yml` and the `.github/workflows/*.yml` files are house-owned but routinely extended:
  ensure the template's tasks/jobs/steps are present. If a template task/job differs, offer
  replace-or-keep for that entry. Owned keys per `project-owned-keys.md`.
- `dprint.json` is JSON: reconcile `lineWidth`, `markdown`, and `plugins` with the leaf-path rules.
  Project-added `includes` entries and `excludes` are owned.
- `.markdownlint-cli2.jsonc` is JSONC: reconcile `config` rules with the leaf-path rules.
  Project-added rule entries are owned.
- `.editorconfig` has no keys to merge — if it differs, offer replace-or-keep.
- `.gitignore` is line-based and additive: ensure the template's lines exist, and keep project-added
  lines without surfacing them as drift.
- `.github/dependabot.yml` is house-owned: ensure the template's ecosystem entries are present, and
  keep project-added entries without surfacing them as drift.
- `LICENSE` is project-owned once present — never reconciled.
