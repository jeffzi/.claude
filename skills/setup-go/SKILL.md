---
name: setup-go
description: Scaffolds or reconciles the house Go tooling config (init | update).
argument-hint: init | update
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion, Bash(cp:*), Bash(ls:*), Bash(mkdir:*), Bash(ln:*), Bash(diff:*), Bash(go *)
# Quality floor: the update reconcile is a key-by-key judgment pass (stale default vs deliberate override); the cheap tier batch-accepts.
model: sonnet
effort: medium
---

# setup-go

Scaffold and maintain the house Go tooling config. The templates in `references/` are the single
source of truth: `init` seeds them into a project, `update` reconciles an existing project against
them without clobbering deliberate local changes.

`$ARGUMENTS` selects the mode: `init` or `update`. If empty, ask which.

## Templates (source of truth)

`${CLAUDE_SKILL_DIR}/references/` holds one standalone config per tool. `init`/`update` run from the
target project's cwd, so always read the source from `${CLAUDE_SKILL_DIR}/references/<template>`,
never a bare relative `references/` path. Each maps to a fixed destination in the project root:

| Template (in `${CLAUDE_SKILL_DIR}/references/`)    | Destination                               |
| -------------------------------------------------- | ----------------------------------------- |
| `go-mod`                                           | `go.mod`                                  |
| `golangci.yml`                                     | `.golangci.yml`                           |
| `golangci-tests.yml`                               | `.golangci.tests.yml`                     |
| `pre-commit-config.yaml`                           | `.pre-commit-config.yaml`                 |
| `dprint-json`                                      | `dprint.json`                             |
| `.markdownlint-cli2.jsonc`                         | `.markdownlint-cli2.jsonc`                |
| `editorconfig`                                     | `.editorconfig`                           |
| `gitignore`                                        | `.gitignore`                              |
| `Taskfile.yml`                                     | `Taskfile.yml`                            |
| `agents-md`                                        | `AGENTS.md`                               |
| `cspell.json`                                      | `cspell.json`                             |
| `.coverage.yml`                                    | `.coverage.yml`                           |
| `dependabot.yml`                                   | `.github/dependabot.yml`                  |
| `github-workflows/actions/setup-dprint/action.yml` | `.github/actions/setup-dprint/action.yml` |
| `github-workflows/prek.yml`                        | `.github/workflows/prek.yml`              |
| `github-workflows/ci.yml`                          | `.github/workflows/ci.yml`                |
| `github-workflows/audit.yml`                       | `.github/workflows/audit.yml`             |
| `github-workflows/publish.yml`                     | `.github/workflows/publish.yml`           |
| `github-workflows/update-tools.yml`                | `.github/workflows/update-tools.yml`      |

Copy to the **Destination** column name, not the template name; create missing destination
directories (`.github/actions/setup-dprint/`, `.github/workflows/`) before copying. Several
templates are stored under neutralized names because their real names would take effect on this
skills repo itself:

- `editorconfig`, `gitignore` — dot-less; a real `.editorconfig`/`.gitignore` in `references/` would
  cascade over the repo.
- `agents-md` — a real `AGENTS.md` would be auto-loaded as agent instructions when editing
  templates.
- `go-mod` — a real `go.mod` in `references/` would be discovered by Go tools traversing up the
  directory tree.
- `golangci.yml` — a real `.golangci.yml` in `references/` would be discovered by golangci-lint.
- `golangci-tests.yml` — dot-less like `golangci.yml`. It is the second golangci-lint config: the
  file cap for `_test.go` files, run by the `golangci-lint-test-size` hook.
- `pre-commit-config.yaml` — a real `.pre-commit-config.yaml` here is discovered and executed by
  this repo's `prek`.
- `dprint-json` — a real `dprint.json` here is discovered by `dprint` and shadows the repo's own
  formatter config for this subtree.

`AGENTS.md` ships with a companion `CLAUDE.md`: in both `init` and `update`, after the copy, ensure
`CLAUDE.md` is a regular file holding `# <project name>`, a blank line, and `@AGENTS.md`. Claude
Code skips `AGENTS.md` whenever a `CLAUDE.md` or `CLAUDE.local.md` applies, so the import is what
loads it; never symlink instead, because the Edit and Write tools don't write through a symlink.
Replace an existing `CLAUDE.md` symlink with the import file. A regular `CLAUDE.md` holding anything
else is never replaced — surface it and let the user decide (usually: merge its content into
`AGENTS.md`, then write the import file).

**Project-owned keys** are listed in `${CLAUDE_SKILL_DIR}/references/project-owned-keys.md`. Exclude
them from every reconcile bucket — never surface as drift.

## init

Seed templates into a project that has none (or is missing some).

1. **Bootstrap `go.mod` and `LICENSE`** — the house tooling requires a `go.mod` (golangci-lint, `go
   tool`, `go test` all operate on a module), and the `tool` directive provides dev tools.
   - `go.mod` **missing** → copy `${CLAUDE_SKILL_DIR}/references/go-mod` (a stub carrying the house
     `go`/`toolchain` directives), then ask the user for the module path with `AskUserQuestion` —
     the path the repository will be hosted at (`github.com/<owner>/<basename>`), or the project
     directory's basename for a module nothing else will import — and set `module` to the answer.
     The stub ships `project` only as a placeholder.
   - `go.mod` **exists** → leave it; `init` never reconciles. `update` merges config (see below).
   - `LICENSE` **missing** → copy `${CLAUDE_SKILL_DIR}/references/LICENSE` (MIT).
   - `LICENSE` **exists** → leave it.
   - `README.md` **missing** → create a one-line stub (`# <name>`).
   - `README.md` **exists** → leave it.
   - **Source skeleton** — golangci-lint and `go build` fail on a module with no `.go` files. After
     a fresh `go.mod` copy, if no `.go` files exist in the project root, ask the user with
     `AskUserQuestion` whether the project is a command or a library, then create one file, where
     `<name>` is the last element of the module path:
     - **Command** → `main.go` with `package main`, an empty `main()`, and a package comment that
       starts with the program name (`// <Name> does X.`).
     - **Library** → `<name>.go` with `package <name>` and a `// Package <name> does X.` comment.
       Never create `main.go` for a library — a root `package main` makes the module root
       non-importable.

     Skip this when `go.mod` already existed — the project owns its layout.
2. For each tooling template, check if the destination exists.
   - **Missing** → copy it verbatim from `${CLAUDE_SKILL_DIR}/references/<template>`.
   - **Exists** → skip it, note it. Never overwrite in `init`; that is `update`'s job.
3. **Install house tools** via the `tool` directive — these are the dev tools every project gets:
   - `go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint`
   - `go get -tool golang.org/x/vuln/cmd/govulncheck`
   - `go get -tool github.com/vladopajic/go-test-coverage/v2`
   - `go mod tidy`
4. Run `go build ./...` to verify the scaffolded project compiles.
5. Report what was created vs skipped.

## update

Bring an existing project's config in line with the current templates. **Additive, never a silent
clobber.**

**Mechanical comparison required.** Never eyeball two Read outputs side by side — visual scanning
across batched tool output misses single-line differences. For every file pair, run `diff
"${CLAUDE_SKILL_DIR}/references/<template>" "<project>/<destination>"` first. Only then inspect the
reported differences key-by-key.

**Destination missing entirely** → copy the template verbatim (as `init` step 2 does), report it as
a seeded file, and skip the diff for that pair.

For each config file, recurse to **leaf paths** — a container present in both (e.g. golangci-lint's
`linters.enable`) with a child missing on one side is a difference at that child, not a match at the
container:

- **Key in template, absent in project** → stage as an _add_ (new house rule).
- **Key matches template** → nothing.
- **Key differs from template**, and it is NOT a project-owned key → stage as a _conflict_. Do not
  overwrite.
- **Key in project, dropped from template** (retired rule) → stage as a _removal candidate_. Do not
  auto-delete.
- **Project-owned key** (listed in `${CLAUDE_SKILL_DIR}/references/project-owned-keys.md`) → leave
  untouched, never surface, and never treat as a removal candidate just because it is absent from
  the project.

A conflict may be a _stale old default_ or a _deliberate override_ — without stored provenance the
skill cannot tell, so never auto-accept; the user decides at the question below.

Then present the staged changes with `AskUserQuestion` so the user decides in one pass — one
question per file that has changes, options like:

- **Apply all** (adds + accept template values for conflicts + removals)
- **Adds only** (new house rules, keep my diverged values, keep retired keys)
- **Review individually** (walk each key)
- **Skip this file**

Apply the chosen edits with `Edit`/`Write`, preserving comments and key order. The per-file
comparison detail lives in `${CLAUDE_SKILL_DIR}/references/reconcile-rules.md`; consult it during
the per-file pass.

After configs are reconciled, run `go build ./...` to verify.

Finish by reporting: files changed and keys added/updated/removed.

## Common mistakes

- **Eyeballing diffs.** Batched Read outputs "compared" visually let single-line differences slip
  through — the `diff` step is mandatory for every file pair.
- **Surfacing project-owned keys as drift.** The user sees noise conflicts on `go.mod` `module` or
  `require` blocks — exclude the owned keys before staging anything.
