# Project-Owned Keys

Keys the template ships with a default value but the project may freely override. Exclude from every
reconcile bucket — read them (so they aren't miscounted as removals) but keep their value as-is.
Never surface as drift.

| File                       | Owned keys                                                                                                                                                                                                                                                         |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `go.mod`                   | `module` path, `go` directive value, `toolchain` directive value, `require`, `tool` (project additions)                                                                                                                                                            |
| `.golangci.yml`            | project-added linter `settings` values beyond the house defaults; the `funlen` limits and the `file-length-limit` `max` (project facts)                                                                                                                            |
| `.golangci.tests.yml`      | the `file-length-limit` `max` (project fact)                                                                                                                                                                                                                       |
| `.coverage.yml`            | `threshold` values (project may raise the floor)                                                                                                                                                                                                                   |
| `.pre-commit-config.yaml`  | every `rev:` value (update-tools owns hook pins); reconcile at hook level, not key level                                                                                                                                                                           |
| `.markdownlint-cli2.jsonc` | project-added rule entries                                                                                                                                                                                                                                         |
| `dprint.json`              | `excludes`, project-added `includes` entries                                                                                                                                                                                                                       |
| `cspell.json`              | `words`, project-added `ignorePaths` entries                                                                                                                                                                                                                       |
| `AGENTS.md`                | Every section except `## Commands`, `## Git hygiene`, `## Linter and type-checker configuration`, `## Project layout`, `## Package and file layout`, `## Doc comments`, `## Spelling (cspell)`; the `### Project facts` values inside `## Package and file layout` |
| `Taskfile.yml`             | project-added tasks; house tasks are reconciled, project additions kept without surfacing as drift                                                                                                                                                                 |
| `.github/workflows/*.yml`  | project-added jobs, steps, and matrix entries; house jobs/steps reconciled, project additions kept                                                                                                                                                                 |
| `LICENSE`                  | entirely project-owned once present (bootstrap-only, never reconciled)                                                                                                                                                                                             |

The golangci-lint v2 `version`, `formatters`, and `linters.enable` list are house rules — reconcile
with the normal add/conflict/removal logic. Project-specific linter `settings` additions (e.g. extra
`revive` rules) are owned.

The `tool` directive in `go.mod` reconciles the **tool set** (which tools are present): a tool the
template ships that the project dropped is a removal candidate; a tool the project added is owned.
Version pins belong to `go get -u -tool`.
