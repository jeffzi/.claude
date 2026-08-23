---
name: setup-ts
description: Scaffolds or reconciles the house TypeScript tooling config (init | update), then chains upgrade-ts.
argument-hint: init | update
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion, Bash(cp:*), Bash(ls:*), Bash(mkdir:*), Bash(ln:*), Bash(diff:*), Skill
# Quality floor: the update reconcile is a key-by-key judgment pass (stale default vs deliberate override); the cheap tier batch-accepts.
model: sonnet
effort: medium
---

# setup-ts

Scaffold and maintain the house TypeScript tooling config. The templates in `references/` are the
single source of truth: `init` seeds them into a project, `update` reconciles an existing project
against them without clobbering deliberate local changes.

`$ARGUMENTS` selects the mode: `init` or `update`. If empty, ask which.

## Templates (source of truth)

`${CLAUDE_SKILL_DIR}/references/` holds one standalone config per tool — no `extends`, no npm
package. `init`/`update` run from the target project's cwd, so always read the source from
`${CLAUDE_SKILL_DIR}/references/<template>`, never a bare relative `references/` path. Each maps to
a fixed destination in the project root:

| Template (in `${CLAUDE_SKILL_DIR}/references/`) | Destination                          |
| ----------------------------------------------- | ------------------------------------ |
| `.oxlintrc.json`                                | `.oxlintrc.json`                     |
| `.oxfmtrc.json`                                 | `.oxfmtrc.json`                      |
| `.markdownlint-cli2.jsonc`                      | `.markdownlint-cli2.jsonc`           |
| `cspell.json`                                   | `cspell.json`                        |
| `fallow.json`                                   | `.fallowrc.json`                     |
| `tsconfig.json`                                 | `tsconfig.json`                      |
| `tsconfig.build.json`                           | `tsconfig.build.json`                |
| `vitest.config.ts`                              | `vitest.config.ts`                   |
| `lefthook.yml`                                  | `lefthook.yml`                       |
| `commitlintrc.json`                             | `.commitlintrc.json`                 |
| `ci.yml`                                        | `.github/workflows/ci.yml`           |
| `audit.yml`                                     | `.github/workflows/audit.yml`        |
| `publish.yml`                                   | `.github/workflows/publish.yml`      |
| `update-tools.yml`                              | `.github/workflows/update-tools.yml` |
| `dependabot.yml`                                | `.github/dependabot.yml`             |
| `editorconfig`                                  | `.editorconfig`                      |
| `gitignore`                                     | `.gitignore`                         |
| `npmrc`                                         | `.npmrc`                             |
| `agents-md`                                     | `AGENTS.md`                          |
| `agents-local-md`                               | `AGENTS.local.md`                    |
| `mcp.json`                                      | `.mcp.json`                          |
| `package.json`                                  | `package.json`                       |

Copy to the **Destination** column name, not the template name; create missing destination
directories (`.github/workflows/`) before copying. `editorconfig`, `gitignore`, and `npmrc` are
stored dot-less, and `agents-md` and `agents-local-md` under neutralized names, because the real
names would take effect on this skills repo itself (an `AGENTS.md` in `references/` would be
auto-loaded as agent instructions when editing templates here).

`AGENTS.local.md` and `.mcp.json` are per-developer files (gitignored). `init` seeds them if
missing; `update` never reconciles them — they are personal overrides.

`AGENTS.md` ships with a companion symlink: in both `init` and `update`, after the copy, ensure
`CLAUDE.md` exists as a symlink to it (`ln -s AGENTS.md CLAUDE.md`). If `CLAUDE.md` already exists
as a regular file, never replace it — surface it and let the user decide (usually: merge its content
into `AGENTS.md`, then symlink).

**Project-owned keys** are listed in `${CLAUDE_SKILL_DIR}/references/project-owned-keys.md`. Exclude
them from every reconcile bucket — never surface as drift.

## init

Seed templates into a project that has none (or is missing some).

1. **Bootstrap `package.json` and `LICENSE`** — the tooling installs as devDependencies, so
   `npm install` needs a `package.json` to install into. An empty project has none, and the install
   fails with `ENOENT` before anything happens.
   - `package.json` **missing** → copy `${CLAUDE_SKILL_DIR}/references/package.json` (a `private`
     ESM stub carrying the house scripts and pinned devDependencies), then set `name` to the target
     project directory's basename — the stub ships `"project"` only as a placeholder.
   - `package.json` **exists** → leave it; `init` never reconciles. `update` merges `scripts` and
     `devDependencies` (see below).
   - `LICENSE` **missing** → copy `${CLAUDE_SKILL_DIR}/references/LICENSE` (MIT).
   - `LICENSE` **exists** → leave it.
2. For each tooling template, check if the destination exists.
   - **Missing** → copy it verbatim from `${CLAUDE_SKILL_DIR}/references/<template>`.
   - **Exists** → skip it, note it. Never overwrite in `init`; that is `update`'s job.
3. Report what was created vs skipped.
4. Bump the seeded devDependencies to current and install them by invoking `Skill(upgrade-ts)` — the
   same step `update` ends with. The template's pinned ranges are floors; `upgrade-ts` refreshes
   them and runs the install, so `init` leaves the project on current versions rather than the
   template's snapshot.

## update

Bring an existing project's config in line with the current templates, then bump packages.
**Additive, never a silent clobber.**

**Mechanical comparison required.** Never eyeball two Read outputs side by side — visual scanning
across batched tool output misses single-line differences. For every file pair, run
`diff "${CLAUDE_SKILL_DIR}/references/<template>" "<project>/<destination>"` first. Only then
inspect the reported differences key-by-key.

For each config file, recurse to **leaf paths** — a container present in both (e.g. oxlint's
`rules`) with a child missing on one side is a difference at that child, not a match at the
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
comparison detail — how each config file is compared and merged — lives in
`${CLAUDE_SKILL_DIR}/references/reconcile-rules.md`; consult it during the per-file pass.

After configs are reconciled, bump the dependencies by invoking `Skill(upgrade-ts)` — do not
reimplement its pinning strategy here.

Finish by reporting: files changed, keys added/updated/removed, and that `Skill(upgrade-ts)` ran.

## Common mistakes

- **Eyeballing diffs.** Batched Read outputs "compared" visually let single-line differences slip
  through — the `diff` step is mandatory for every file pair.
- **Surfacing project-owned keys as drift.** The user sees noise conflicts on `cspell.json` words or
  `tsconfig` paths — exclude the owned keys before staging anything.
