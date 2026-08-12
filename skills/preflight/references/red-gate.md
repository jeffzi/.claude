# Red Gate Protocol — Formatting Branch, One Repair, Restore Decision

Applies when a fix-round gate goes red: the fix gate (step 4, snapshot `preflight-snap-1`) and the
corrective gate (step 5, snapshot `preflight-snap-2`). `<scripts>` and `<scratchpad>` mean the paths
already resolved in the rendered SKILL.md commands in context.

- **Red on formatting alone** (`FAILING:` names only the project's format check): run the project's
  own formatter — the exact tool the failing check invokes, never a substitute (no reaching for
  biome in an oxfmt project) — once, scoped to the files preflight edited, then re-run the gate
  script, both halves (the script numbers the new captures itself). The entry gate was green, so any
  new format failure lives in those files; formatting untouched files is outside the snapshot and
  the restore guarantee. Record the Gates row as `🔴→✅ (formatter re-run)`, never a plain ✅. A
  second red, or any non-format red, takes the repair branch below.
- **Red otherwise — one repair attempt before anyone is asked.** A regression a mender introduced is
  something a mender can remove; the user question is the fallback, never the first response.
  Extract the implicated files (the files the failing sub-checks name in the captures) and widen
  each to its whole mender group — a group is the atomic unit for repairing exactly as it is for
  fixing, and it includes any file the group's mender created. Dispatch one `code-mender` per
  implicated group, in parallel, whose finding is the gate evidence itself: the failing sub-check
  names, the relevant capture excerpt, and the group's files — "these checks went red after this
  group's edits; repair the regression." The mender diagnoses in its own context; the no-diagnosis
  rule in step 4 still binds you. Add the repair menders' edits to the edited-files set, then re-run
  the gate script, both halves. Green → record the Gates row as `🔴→✅ (gate repair)` and proceed —
  a regression a mender introduced and the repair removed is internal churn, no report row. Still
  red → the restore decision below. **One repair attempt per gate, ever** — a second red at the same
  gate is never answered with another mender.
- **Red after the repair attempt — the restore decision belongs to the user.** Re-extract the
  implicated files from the newest captures and widen each to its whole mender group (repair edits
  included) — restoring half an atomic fix leaves orphans. Then use **AskUserQuestion** with exactly
  these three options and wait:
  1. **Restore everything** →
     `node <scripts>/snapshot.ts restore <scratchpad>/<snapshot> --edited <edited files>`, then
     report status 🔄 **REVERTED** with the failing output and the fixes attempted, jump to step 7.
  2. **Restore only the implicated files** →
     `node <scripts>/snapshot.ts restore <scratchpad>/<snapshot> --only <implicated files>
     --edited <edited files>`,
     then re-run the gate script. Green → move the reverted files' findings to Issues Reported
     ("reverted at red gate — user choice"), adjust the tally, and continue the pipeline with the
     surviving fixes. Still red → ask again with options 1 and 3 only.
  3. **Leave the tree as it is** (user takes over) → stop, report status 🚫 **HANDED OFF** — gate
     red, fixes left in the tree at user request — including the failing output, the files preflight
     changed, and the exact restore command with the snapshot path (noting it runs from the repo
     root) so recovery is one paste. Jump to step 7.
