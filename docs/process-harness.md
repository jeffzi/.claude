# Process skills and project harnesses

Some skills are **process skills**: methodology-heavy, project-agnostic workflows (a hardening
round, an audit, a migration sweep). The lifecycle, discipline, and vocabulary are universal — but
the skill cannot run without project-specific _tooling_: which build command produces the artifact,
which areas to scan, which skills to load per file kind, which invariants finders must respect.

This doc describes the pattern that separates the two: a **general process skill** plus a **project
harness file** it reads at runtime. It is an extension to the overlay architecture in
[`docs/languages.md`](languages.md), not a replacement.

## Why the existing patterns don't fit

**DSD (Domain Skill Detection) answers the wrong question.** The `code-*` / `test-*` overlay chain
detects import patterns to answer "which _rules_ apply to this _file_?" — it overlays content. A
process skill needs "which _commands_ apply to this _project_?" — it needs tooling config. Different
shape: DSD keys on file content and adds prose; a harness keys on the repo and supplies executable
command blocks, scan areas, and dispatch tables. Forcing tooling config through import detection
would be a category error.

**Skill shadowing forces a full copy.** A project-level skill at `<repo>/.claude/skills/X/SKILL.md`
shadows the global `~/.claude/skills/X/`. To customize one command you must copy the entire skill —
methodology and all — and the copies drift. Every fix to the methodology then has to be applied N
times, once per project that shadowed it.

## The pattern

- **General skill** at `~/.claude/skills/X/SKILL.md` owns the entire methodology: lifecycle, gates,
  classification, bright lines, rationalizations. It references nothing project-specific.
- **Project harness** at `<repo-root>/.claude/X.md` owns only the project's tooling: commands, scan
  areas, skill dispatch, domain invariants. It is a config document, not a skill (no frontmatter).
- The skill reads the harness from the well-known path **at runtime**, early in its body. If the
  harness is absent (or the directory is not a git repo), the skill **stops with a clear error**
  pointing at the template — it does not guess or fall back to defaults.

The harness is the single coupling point. The methodology lives in exactly one place and is fixed
once for every project; each project supplies its tooling once.

## Precedent: preflight's CLAUDE.md lookup

This is the same move `preflight` already makes: it reads conventions from CLAUDE.md at known
locations (`./`, repo root, `~/.claude/`) rather than embedding any one project's conventions. The
harness pattern generalizes that — a dedicated, structured config file at a well-known path, read by
a skill that owns the process. It deliberately does **not** follow the DSD overlay chain, which is
import-based and the wrong shape for process config.

## When to use this pattern

Use it when **the methodology is the bulk of the skill (>60%) and the project config is a separable
concern** — a clean seam between "how the process works" and "what this project plugs into it."

Keep a **monolithic project skill** when the skill is inherently project-specific with no reuse
potential — when factoring out a harness would leave a general skill so thin it carries no
methodology worth sharing.

## Canonical example

[`skills/harden/SKILL.md`](../skills/harden/SKILL.md) is the reference implementation. It owns the
hardening-round lifecycle, finding taxonomy, ledger protocol, diff-gate framework, bright lines, and
rationalization table. It reads `<repo-root>/.claude/harden.md` for the project's scan areas,
baseline-snapshot and per-task-gate commands, skill dispatch, and domain doctrines. Start a new
harness from [`docs/templates/harden-harness.md`](templates/harden-harness.md).

## See also

- [`docs/languages.md`](languages.md) — the content-overlay (DSD) architecture for `code-*` /
  `test-*` skills, the sibling pattern this one is contrasted against.
- [`docs/templates/harden-harness.md`](templates/harden-harness.md) — the harness skeleton.
