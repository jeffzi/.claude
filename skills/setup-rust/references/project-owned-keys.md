# Project-Owned Keys

Keys the template ships with a default value but the project may freely override. Exclude from every
reconcile bucket -- read them (so they aren't miscounted as removals) but keep their value as-is.
Never surface as drift.

| File                       | Owned keys                                                                                                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Cargo.toml`               | All of `[package]` (name, version, description, authors, repository, categories, keywords), `[dependencies]`, `[dev-dependencies]`, `[features]`, `[lib]`, `[[bin]]` |
| `Cargo.toml`               | `rust-version` (project may lower the floor), `edition` (project may lag) -- reconcile presence only, never value                                                    |
| `rust-toolchain.toml`      | `channel` value when pinned to a specific version (e.g. `"1.98.0"` vs `"stable"`)                                                                                    |
| `deny.toml`                | `[advisories] ignore` entries (project-specific exceptions), `[bans] deny` / `skip` entries                                                                          |
| `.pre-commit-config.yaml`  | every `rev:` value (update-tools owns hook pins); reconcile at hook level, not key level                                                                             |
| `.markdownlint-cli2.jsonc` | project-added rule entries                                                                                                                                           |
| `dprint.json`              | `excludes`, project-added `includes` entries                                                                                                                         |
| `cspell.json`              | `words`, project-added `ignorePaths` entries                                                                                                                         |
| `AGENTS.md`                | Every section except `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, `## Doc comments`, `## Spelling (cspell)`                          |
| `Taskfile.yml`             | project-added tasks; house tasks are reconciled, project additions kept without surfacing as drift                                                                   |
| `.github/workflows/*.yml`  | project-added jobs, steps, and matrix entries; house jobs/steps reconciled, project additions kept                                                                   |
| `LICENSE`                  | entirely project-owned once present (bootstrap-only, never reconciled)                                                                                               |

`[lints.rust]` and `[lints.clippy]` are house rules -- reconcile with the normal
add/conflict/removal logic.
