---
name: setup-py
description: Scaffolds or reconciles the house Python tooling config (init | update), then chains upgrade-py.
argument-hint: init | update
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion, Bash(cp:*), Bash(ls:*), Bash(mkdir:*), Bash(ln:*), Bash(diff:*), Skill
# Quality floor: the update reconcile is a key-by-key judgment pass (stale default vs deliberate override); the cheap tier batch-accepts.
model: sonnet
effort: medium
---

# setup-py

Scaffold and maintain the house Python tooling config. The templates in `references/` are the single
source of truth: `init` seeds them into a project, `update` reconciles an existing project against
them without clobbering deliberate local changes.

`$ARGUMENTS` selects the mode: `init` or `update`. If empty, ask which.

## Templates (source of truth)

`${CLAUDE_SKILL_DIR}/references/` holds one standalone config per tool. `init`/`update` run from the
target project's cwd, so always read the source from `${CLAUDE_SKILL_DIR}/references/<template>`,
never a bare relative `references/` path. Each maps to a fixed destination in the project root:

| Template (in `${CLAUDE_SKILL_DIR}/references/`) | Destination                          |
| ----------------------------------------------- | ------------------------------------ |
| `pyproject.toml`                                | `pyproject.toml`                     |
| `pre-commit-config.yaml`                        | `.pre-commit-config.yaml`            |
| `dprint-json`                                   | `dprint.json`                        |
| `.markdownlint-cli2.jsonc`                      | `.markdownlint-cli2.jsonc`           |
| `cspell.json`                                   | `cspell.json`                        |
| `editorconfig`                                  | `.editorconfig`                      |
| `gitignore`                                     | `.gitignore`                         |
| `python-version`                                | `.python-version`                    |
| `agents-md`                                     | `AGENTS.md`                          |
| `Taskfile.yml`                                  | `Taskfile.yml`                       |
| `dependabot.yml`                                | `.github/dependabot.yml`             |
| `github-workflows/prek.yml`                     | `.github/workflows/prek.yml`         |
| `github-workflows/pytest.yml`                   | `.github/workflows/pytest.yml`       |
| `github-workflows/audit.yml`                    | `.github/workflows/audit.yml`        |
| `github-workflows/publish.yml`                  | `.github/workflows/publish.yml`      |
| `github-workflows/update-tools.yml`             | `.github/workflows/update-tools.yml` |

Copy to the **Destination** column name, not the template name; create missing destination
directories (`.github/workflows/`) before copying. Several templates are stored under neutralized
names because their real names would take effect on this skills repo itself:

- `editorconfig`, `gitignore`, `python-version` — dot-less; a real
  `.editorconfig`/`.gitignore`/`.python-version` in `references/` would cascade over the repo.
- `agents-md` — a real `AGENTS.md` would be auto-loaded as agent instructions when editing
  templates.
- `pre-commit-config.yaml` — a real `.pre-commit-config.yaml` here is discovered and **executed** by
  this repo's `prek`, running the template's hooks against `references/`.
- `dprint-json` — a real `dprint.json` here is discovered by `dprint` and shadows the repo's own
  formatter config for this subtree.

`AGENTS.md` ships with a companion symlink: in both `init` and `update`, after the copy, ensure
`CLAUDE.md` exists as a symlink to it (`ln -s AGENTS.md CLAUDE.md`). If `CLAUDE.md` already exists
as a regular file, never replace it — surface it and let the user decide (usually: merge its content
into `AGENTS.md`, then symlink).

**Project-owned keys** are listed in `${CLAUDE_SKILL_DIR}/references/project-owned-keys.md`. Exclude
them from every reconcile bucket — never surface as drift.

## init

Seed templates into a project that has none (or is missing some).

1. **Bootstrap `pyproject.toml` and `LICENSE`** — `uv sync` needs a `pyproject.toml` to resolve
   against, and the house tooling installs from the `dev` dependency group.
   - `pyproject.toml` **missing** → copy `${CLAUDE_SKILL_DIR}/references/pyproject.toml` (a stub
     carrying the house `[tool.*]` config and the pinned `dev` group), then set `[project].name` to
     the target project directory's basename — the stub ships `"project"` only as a placeholder.
   - `pyproject.toml` **exists** → leave it; `init` never reconciles. `update` merges the `[tool.*]`
     config and the `dev` group (see below).
   - `LICENSE` **missing** → copy `${CLAUDE_SKILL_DIR}/references/LICENSE` (MIT).
   - `LICENSE` **exists** → leave it.
   - `README.md` **missing** → create a one-line stub (`# <name>`). The stub `pyproject.toml`
     declares `readme = "README.md"`, so the `uv_build` backend fails to build without it.
   - `README.md` **exists** → leave it.
   - **Package skeleton** — the stub's `uv_build` backend builds the project itself, so `uv sync`
     needs an importable package. After a fresh `pyproject.toml` copy, if neither `src/<name>/` nor
     a top-level `<name>/` package exists (`<name>` = the basename set above, dashes → underscores),
     create `src/<name>/__init__.py` (empty) and an empty `src/<name>/py.typed` marker — the latter
     is what makes the package's type annotations visible to downstream consumers. Skip this when
     `pyproject.toml` already existed — the project owns its layout.
2. For each tooling template, check if the destination exists.
   - **Missing** → copy it verbatim from `${CLAUDE_SKILL_DIR}/references/<template>`.
   - **Exists** → skip it, note it. Never overwrite in `init`; that is `update`'s job.
3. Report what was created vs skipped.
4. Bump the seeded dependencies to current and install them by invoking `Skill(upgrade-py)` — the
   same step `update` ends with. The template's pinned ranges are floors; `upgrade-py` refreshes
   them, syncs the prek hook pins, and runs the install, so `init` leaves the project on current
   versions rather than the template's snapshot.

## update

Bring an existing project's config in line with the current templates, then bump packages.
**Additive, never a silent clobber.**

**Mechanical comparison required.** Never eyeball two Read outputs side by side — visual scanning
across batched tool output misses single-line differences. For every file pair, run
`diff "${CLAUDE_SKILL_DIR}/references/<template>" "<project>/<destination>"` first. Only then
inspect the reported differences key-by-key.

For each config file, recurse to **leaf paths** — a container present in both (e.g. ruff's
`lint.ignore`, or a `[tool.*]` table) with a child missing on one side is a difference at that
child, not a match at the container:

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
comparison detail — which tables, sections, and lines to merge for each config file — lives in
`${CLAUDE_SKILL_DIR}/references/reconcile-rules.md`; consult it during the per-file pass.

After configs are reconciled, bump the dependencies by invoking `Skill(upgrade-py)` — do not
reimplement its pinning strategy here.

Finish by reporting: files changed, keys added/updated/removed, and that `Skill(upgrade-py)` ran.
