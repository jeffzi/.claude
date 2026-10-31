---
name: setup-rust
description: Scaffolds or reconciles the house Rust tooling config (init | update).
argument-hint: init | update
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion, Bash(cp:*), Bash(ls:*), Bash(mkdir:*), Bash(ln:*), Bash(diff:*), Bash(cargo check *)
# Quality floor: the update reconcile is a key-by-key judgment pass (stale default vs deliberate override); the cheap tier batch-accepts.
model: sonnet
effort: medium
---

# setup-rust

Scaffold and maintain the house Rust tooling config. The templates in `references/` are the single
source of truth: `init` seeds them into a project, `update` reconciles an existing project against
them without clobbering deliberate local changes.

`$ARGUMENTS` selects the mode: `init` or `update`. If empty, ask which.

## Templates (source of truth)

`${CLAUDE_SKILL_DIR}/references/` holds one standalone config per tool. `init`/`update` run from the
target project's cwd, so always read the source from `${CLAUDE_SKILL_DIR}/references/<template>`,
never a bare relative `references/` path. Each maps to a fixed destination in the project root:

| Template (in `${CLAUDE_SKILL_DIR}/references/`)    | Destination                               |
| -------------------------------------------------- | ----------------------------------------- |
| `Cargo.toml`                                       | `Cargo.toml`                              |
| `rust-toolchain.toml`                              | `rust-toolchain.toml`                     |
| `rustfmt.toml`                                     | `rustfmt.toml`                            |
| `deny.toml`                                        | `deny.toml`                               |
| `pre-commit-config.yaml`                           | `.pre-commit-config.yaml`                 |
| `dprint-json`                                      | `dprint.json`                             |
| `.markdownlint-cli2.jsonc`                         | `.markdownlint-cli2.jsonc`                |
| `editorconfig`                                     | `.editorconfig`                           |
| `gitignore`                                        | `.gitignore`                              |
| `Taskfile.yml`                                     | `Taskfile.yml`                            |
| `agents-md`                                        | `AGENTS.md`                               |
| `cspell.json`                                      | `cspell.json`                             |
| `dependabot.yml`                                   | `.github/dependabot.yml`                  |
| `github-workflows/actions/setup-dprint/action.yml` | `.github/actions/setup-dprint/action.yml` |
| `github-workflows/ci.yml`                          | `.github/workflows/ci.yml`                |
| `github-workflows/audit.yml`                       | `.github/workflows/audit.yml`             |
| `github-workflows/publish.yml`                     | `.github/workflows/publish.yml`           |
| `github-workflows/update-tools.yml`                | `.github/workflows/update-tools.yml`      |

Copy to the **Destination** column name, not the template name; create missing destination
directories (`.github/actions/setup-dprint/`, `.github/workflows/`) before copying. Several
templates are stored under neutralized names because their real names would take effect on this
skills repo itself:

- `editorconfig`, `gitignore` -- dot-less; a real `.editorconfig`/`.gitignore` in `references/`
  would cascade over the repo.
- `agents-md` -- a real `AGENTS.md` would be auto-loaded as agent instructions when editing
  templates.
- `pre-commit-config.yaml` -- a real `.pre-commit-config.yaml` here is discovered and executed by
  this repo's `prek`.
- `dprint-json` -- a real `dprint.json` here is discovered by `dprint` and shadows the repo's own
  formatter config for this subtree.

`AGENTS.md` ships with a companion `CLAUDE.md`: in both `init` and `update`, after the copy, ensure
`CLAUDE.md` is a regular file holding `# <project name>`, a blank line, and `@AGENTS.md`. Claude
Code skips `AGENTS.md` whenever a `CLAUDE.md` or `CLAUDE.local.md` applies, so the import is what
loads it; never symlink instead, because the Edit and Write tools don't write through a symlink.
Replace an existing `CLAUDE.md` symlink with the import file. A regular `CLAUDE.md` holding anything
else is never replaced -- surface it and let the user decide (usually: merge its content into
`AGENTS.md`, then write the import file).

**Project-owned keys** are listed in `${CLAUDE_SKILL_DIR}/references/project-owned-keys.md`. Exclude
them from every reconcile bucket -- never surface as drift.

## init

Seed templates into a project that has none (or is missing some).

1. **Bootstrap `Cargo.toml` and `LICENSE`** -- the tooling configs reference the manifest, and
   `cargo check` needs a valid `Cargo.toml`.
   - `Cargo.toml` **missing** -> copy `${CLAUDE_SKILL_DIR}/references/Cargo.toml` (a stub carrying
     the house `[lints]` config and edition/rust-version), then set `[package].name` to the target
     project directory's basename (lowercase, hyphens) -- the stub ships `"project"` only as a
     placeholder.
   - `Cargo.toml` **exists** -> leave it; `init` never reconciles. `update` merges the `[lints]`
     config (see below).
   - `LICENSE` **missing** -> copy `${CLAUDE_SKILL_DIR}/references/LICENSE` (MIT).
   - `LICENSE` **exists** -> leave it.
   - **Source skeleton** -- a manifest with no `src/lib.rs`, `src/main.rs`, `[lib]`, or `[[bin]]`
     has no targets, so `cargo check` fails. After a fresh `Cargo.toml` copy, if `src/lib.rs` does
     not exist, create it (empty). Skip this when `Cargo.toml` already existed -- the project owns
     its layout.
2. For each tooling template, check if the destination exists.
   - **Missing** -> copy it verbatim from `${CLAUDE_SKILL_DIR}/references/<template>`.
   - **Exists** -> skip it, note it. Never overwrite in `init`; that is `update`'s job.
3. Run `cargo check` to verify the scaffolded project compiles.
4. Report what was created vs skipped. Include a **Prerequisites** note listing the cargo
   subcommands the seeded config requires but does not install:
   - `cargo-nextest` — <https://nexte.st/>
   - `cargo-llvm-cov` — <https://github.com/taiki-e/cargo-llvm-cov>
   - `cargo-deny` — <https://github.com/EmbarkStudios/cargo-deny>
   - `cargo-machete` — <https://github.com/bnjbvr/cargo-machete>

## update

Bring an existing project's config in line with the current templates. **Additive, never a silent
clobber.**

**Mechanical comparison required.** Never eyeball two Read outputs side by side -- visual scanning
across batched tool output misses single-line differences. For every file pair, run `diff
"${CLAUDE_SKILL_DIR}/references/<template>" "<project>/<destination>"` first. Only then inspect the
reported differences key-by-key.

**Destination missing entirely** -> copy the template verbatim (as `init` step 2 does), report it as
a seeded file, and skip the diff for that pair.

For each config file, recurse to **leaf paths** -- a container present in both (e.g. the `[lints]`
table) with a child missing on one side is a difference at that child, not a match at the container:

- **Key in template, absent in project** -> stage as an _add_ (new house rule).
- **Key matches template** -> nothing.
- **Key differs from template**, and it is NOT a project-owned key -> stage as a _conflict_. Do not
  overwrite.
- **Key in project, dropped from template** (retired rule) -> stage as a _removal candidate_. Do not
  auto-delete.
- **Project-owned key** (listed in `${CLAUDE_SKILL_DIR}/references/project-owned-keys.md`) -> leave
  untouched, never surface, and never treat as a removal candidate just because it is absent from
  the project.

A conflict may be a _stale old default_ or a _deliberate override_ -- without stored provenance the
skill cannot tell, so never auto-accept; the user decides at the question below.

Then present the staged changes with `AskUserQuestion` so the user decides in one pass -- one
question per file that has changes, options like:

- **Apply all** (adds + accept template values for conflicts + removals)
- **Adds only** (new house rules, keep my diverged values, keep retired keys)
- **Review individually** (walk each key)
- **Skip this file**

Apply the chosen edits with `Edit`/`Write`, preserving comments and key order. The per-file
comparison detail lives in `${CLAUDE_SKILL_DIR}/references/reconcile-rules.md`; consult it during
the per-file pass.

After configs are reconciled, run `cargo check` to verify.

Finish by reporting: files changed and keys added/updated/removed.

## Common mistakes

- **Eyeballing diffs.** Batched Read outputs "compared" visually let single-line differences slip
  through -- the `diff` step is mandatory for every file pair.
- **Surfacing project-owned keys as drift.** The user sees noise conflicts on `Cargo.toml`
  `[package]` fields or `[dependencies]` -- exclude the owned keys before staging anything.
