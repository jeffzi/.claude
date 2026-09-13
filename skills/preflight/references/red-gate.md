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
  Extract the implicated files and widen each to its whole mender group — a group is the atomic unit
  for repairing exactly as it is for fixing, and it includes any file the group's mender created.
  **A failing test is evidence, not an implicated file.** When a failing sub-check names a test file
  no step 4 mender edited, the implicated files are the edited production files that test exercises
  — the modules in the capture's traceback, or the ones the test imports (`grep -l` on the test's
  import lines is not reading a target file); when the captures cannot settle it, every edited code
  file is implicated. A test file joins the edit targets only when a step 4 mender edited it. Before
  dispatching, snapshot every evidence test file the step 4 snapshot does not already hold: `node
  <scripts>/snapshot.ts save <scratchpad>/preflight-snap-repair <test files>`. Dispatch one
  `code-mender` per implicated group, in parallel, whose finding is the gate evidence itself: the
  failing sub-check names, the relevant capture excerpt, the group's files, the failing test files
  listed under `Evidence (read-only):`, `Behavior: preserve`, and this sentence verbatim: "These
  checks went red after this group's edits. Repair means restoring the behavior the failing test
  pins: revert or adjust the production edit. The test's assertions and expected values are the
  specification — never edit them." The mender diagnoses in its own context; the no-diagnosis rule
  in step 4 still binds you. **Read the repair reports before re-running the gate.** A repair
  mender's Behavior notes describe the restoration and disqualify nothing; a touched test file does.
  A repair that touched a test file — an assertion, an expected value, a parametrize row — defeated
  the detector instead of repairing the regression: restore that group's files and the test file
  from their snapshots (`--only`), move the group's findings to Issues Reported (`reverted at red
  gate — repair edited a test expectation`), and drop the files from the edited set. Add the
  surviving repair edits to the edited-files set, then re-run the gate script, both halves. Green →
  record the Gates row as `🔴→✅ (gate repair)` and proceed — a regression a mender introduced and
  the repair removed is internal churn, no report row. Still red → the restore decision below. **One
  repair attempt per gate, ever** — a second red at the same gate is never answered with another
  mender.
- **Red after the repair attempt — the restore decision belongs to the user.** Re-extract the
  implicated files from the newest captures and widen each to its whole mender group (repair edits
  included) — restoring half an atomic fix leaves orphans. Then use **AskUserQuestion** with exactly
  these three options and wait:
  1. **Restore everything** → `node <scripts>/snapshot.ts restore <scratchpad>/<snapshot> --edited
     <edited files>`, then report status 🔄 **REVERTED** with the failing output and the fixes
     attempted, jump to step 7.
  2. **Restore only the implicated files** → `node <scripts>/snapshot.ts restore
     <scratchpad>/<snapshot> --only <implicated files> --edited <edited files>`, then re-run the
     gate script. Green → move the reverted files' findings to Issues Reported ("reverted at red
     gate — user choice"), adjust the tally, and continue the pipeline with the surviving fixes.
     Still red → ask again with options 1 and 3 only.
  3. **Leave the tree as it is** (user takes over) → stop, report status 🚫 **HANDED OFF** — gate
     red, fixes left in the tree at user request — including the failing output, the files preflight
     changed, and the exact restore command with the snapshot path (noting it runs from the repo
     root) so recovery is one paste. Jump to step 7.
