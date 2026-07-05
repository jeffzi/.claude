<!--
  Project hardening harness — read at runtime by `Skill(harden)` from `<repo-root>/.claude/harden.md`.

  The `harden` skill owns the methodology (lifecycle, classification, ledger, bright lines). This
  file supplies the project-specific tooling the skill cannot know: where to scan, how to gate, which
  skills to load, and which invariants finders must respect.

  Copy this file to `<repo-root>/.claude/harden.md` and fill in every section. This template has no
  frontmatter — it is a config document, not a skill.

  Required sections: Scan Areas, Skill Dispatch, Domain Doctrines.
  Optional: Diff Harness (only for projects with compiled or generated output), Round-Completion
  Gate, Common Mistakes, Rationalizations (the last two optional but recommended).
-->

# Hardening Harness — {Project}

## Scan Areas

<!--
  The harden skill dispatches one parallel read-only finder agent per area in audit fan-out (step 1).
  List areas by domain boundary — module, subsystem, layer, contract — NOT by file. A good area is
  small enough for one agent to hold and large enough that a bug could hide across its files.
-->

- **{area-name}** — {what it covers, where it lives}
- **{area-name}** — {what it covers, where it lives}
- ...

## Diff Harness

<!--
  OPTIONAL — include only if the project has compiled or generated output whose bytes must stay
  identical across a refactor (codegen, transpilation, a build artifact). Pure interpreted codebases
  delete this whole section; their per-task gate is just the test suite, and the round has no Task 0.

  The harden skill reads the command blocks below verbatim and runs them as opaque blocks. It does
  not parse them — it requires them to exit 0.
-->

### Baseline Snapshot (Task 0)

<!--
  Commands to build the output and snapshot it to a baseline location. ALWAYS run from a clean
  working tree (commit first). Include any cleanup of stale snapshot directories — a stale baseline
  silently passes every gate.
-->

```bash
# build + snapshot to a baseline location; wipe stale snapshots first
```

### Per-Task Gate

<!--
  Commands to rebuild, diff against the baseline, and run the relevant tests. Must be cheap enough to
  run after EVERY task. The diff gates the output; the tests gate behavior the diff cannot see.
-->

```bash
# rebuild && diff against baseline && run relevant tests
```

### Corpora

<!--
  What each snapshot covers and its blind spots. If the project builds multiple variants
  (debug/release, checked/stripped), snapshot ALL of them and explain what each one misses — a single
  variant gates only the code shapes it happens to contain.
-->

- **{corpus / variant}** — covers {…}; blind to {…}
- **{corpus / variant}** — covers {…}; blind to {…}

### Diff Acceptability

<!--
  Project-specific rules layered on top of the general Diff Gates by Task Type table in the skill.
  State what counts as a failure beyond a literal byte change (e.g. "a shifted generated identifier
  is a failure — names are allocated by transform order, so a shift means the order changed").
-->

- {rule}
- {rule}

## Round-Completion Gate

<!--
  OPTIONAL — commands run once after the round's last task is committed (typically the full test
  suite plus linters). This is additive: the per-task gate still runs after every task; this gate
  covers what is too slow to run per task.
-->

```bash
# full suite + linters
```

## Skill Dispatch

<!--
  Which skills to load during execution (step 5), mapped by the Scan Areas above. The harden skill
  loads these per area touched. Map area → `Skill(code-*)` / `Skill(test-*)`.
-->

| Area / file kind    | Skill to load        |
| ------------------- | -------------------- |
| {area or file kind} | `Skill(code-{lang})` |
| tests               | `Skill(test-{lang})` |

## Domain Doctrines

<!--
  Project-specific invariants carried across every round — the "always true" rules finders and
  verifiers must know to classify a finding correctly. These are the non-obvious constraints that
  make a plausible-looking change a bug (e.g. "validate-then-emit" in a compiler plugin, "no
  allocations in the hot path" in a game engine).
-->

- **{doctrine}** — {what it requires and why}
- **{doctrine}** — {what it requires and why}

## Common Mistakes

<!--
  OPTIONAL but recommended. Project-specific mistakes that produce a false green (e.g. snapshotting
  before rebuilding, snapshotting only one variant).
-->

| Mistake   | Consequence   |
| --------- | ------------- |
| {mistake} | {consequence} |

## Rationalizations

<!--
  OPTIONAL but recommended. Project-specific excuses that signal a failed task, in the skill's
  Excuse / Reality format.
-->

| Excuse     | Reality   |
| ---------- | --------- |
| "{excuse}" | {reality} |
