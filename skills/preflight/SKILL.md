---
name: preflight
description: >
  Gated pre-commit review pipeline: entry gate, parallel review lenses, one verified fix pass,
  exit gate.
argument-hint: Optional path or commit ref (defaults to changes since last push)
disable-model-invocation: true
# Slash-only (disable-model-invocation), so both declarations are live:
model: opus # orchestrates a multi-agent pipeline with snapshot/restore decisions
effort: high # gate verdicts and restore decisions must not be shortcut
---

# Preflight

Automated pre-commit review: a gated pipeline with one verified fix pass. Not a loop — there are no
iterations, no ledger, no cross-round dedup.

**Core principle:** High precision over high recall. Of the findings the review agents return, only
those scored ≥ 75 are auto-fixed; the rest are reported, not applied.

**Invariant:** Never leave the tree worse than it was found. Every edit round is preceded by a
snapshot and followed by a gate. On a red gate the snapshot guarantees recovery — and its scope is
the user's choice (full, partial, or none; steps 4–5), never a silent loss of good fixes. The
snapshot is recovery, the gate is detection — neither substitutes for the other.

**Scripts:** the mechanical steps run through two helpers in this skill's `scripts/` directory,
invoked with plain `node` (v22.18+). `gate.ts` runs both gate halves, auto-numbers its capture
files, and prints a machine-readable verdict with a `FAILING:` line naming red sub-checks. Its exit
codes: 0 green, 1 red (a verdict, not an error), 2 infrastructure failure — exit 2 is never a gate
verdict; surface it and stop. `snapshot.ts` saves and restores manifest-aware tar snapshots; a full
restore deletes mender-created files, a `--only` restore touches nothing beyond the files it names.
Both snapshot commands run from the repo root — restore included.

**Gate** = the project's checkers **and** tests. Not one or the other.

**The orchestrator routes; it never reads target files.** Step 1 needs filenames, step 3's prompts
carry paths and diffs, and every lens reads its own files in its own fresh context. The only file
contents you ever load: the build-config files consulted to resolve the gate commands (step 1) and
the gate capture files. Reading a target file "to understand the code" or "before dispatching" is
context stolen from triage and the report — the steps only you can do.

## Context

- Argument: $ARGUMENTS
- Uncommitted changes: !`git status --porcelain`
- Commits since last push:
  !`git log @{u}..HEAD --oneline 2>/dev/null || echo "(no upstream or up to date)"`

> **Note:** Context above is orientation only. Step 1's file collection is the authoritative source
> of target files.

**Announce at start:** "✈️ Preflight check initiated for [files/path]..."

**Status budget:** After the start announcement, at most ONE short status line per step transition —
fixed shape, `Step 3/7: review lenses dispatched.` — and nothing else until Step 7's Summary Report.
Never findings, issue counts, gate verdicts, or any results content: those exist only in the report
— and the transition lines themselves carry none of it: `Step 4/7: menders
dispatched.` is complete;
never append what was found, promoted, scored, or adjudicated. A task notification or wakeup is NOT
a demand for output — on a wakeup with nothing new to transition to, end the turn with no text at
all; the empty turn IS the correct output, not a failure to respond. `Step N/7 in progress.` exists
solely as the reply to the harness's literal "no visible output" auto-continuation message; emitting
it on an ordinary wakeup is a budget violation. About to write a second sentence anywhere? That's
the signal to keep working instead.

## Execution Sequence

**Execute steps 1-7 in order. Only stop after step 7.**

### Task Management (MANDATORY)

**At the very start**, use the **TaskCreate** tool to create ALL 7 tasks:

| # | Task subject                       | activeForm                   |
| - | ---------------------------------- | ---------------------------- |
| 1 | Setup: files and gate commands     | Detecting files and commands |
| 2 | Entry gate                         | Running entry gate           |
| 3 | Review: all lenses, one pass       | Reviewing                    |
| 4 | Triage and fix                     | Triaging and fixing          |
| 5 | Post-fix scan and fix verification | Checking applied fixes       |
| 6 | Exit gate: full suite              | Running exit gate            |
| 7 | Generate summary report            | Generating summary           |

**As you work**, use the **TaskUpdate** tool: `in_progress` when starting a step, `completed` when
finishing it.

⚠️ **HARD RULE: You cannot stop while ANY task is incomplete.** A hard stop (red gate) does not
suspend this rule — it jumps the pipeline: mark the skipped tasks `completed` (nothing remains to do
on them), run task 7, and report the stop status.

---

### Step 1: Setup

- [ ] Disambiguate argument (commit range vs commit ref vs path — see rules below)
- [ ] Get target files (path arg or git diff)
- [ ] Bucket each target file using the **Language Dispatch for test-\* and code-\*** table in
      `rules/skill-loading.md` (already in session context). For each file, look up its extension:
      if the file path matches one of the test-pattern globs for that row → test files; known
      extension but not matching a test pattern → code files; `.md`, `README*`, `CHANGELOG*` → doc
      files; extension not in the table → still review: test files if the filename matches a generic
      test pattern (`test_*`, `*_test.*`, `*.test.*`, `*_spec.*`, `*Tests.*`), otherwise code files
      (the `vet-code`/`vet-test` agents fall back to hub-only review when no dispatch row exists).
      **Exception — data and asset files are not review targets** (doc-named files bucket as docs
      first; this exception never claims them): serialized/config data (`.json`, `.jsonl`, `.yaml`,
      `.yml`, `.toml`, `.ini`, `.xml`, `.csv`, `.tsv`, `.txt` — fixtures and golden files included),
      lockfiles, media and binaries, generated artifacts (`*.min.*`, `*.map`, `dist/`/`build/`), and
      test snapshots. Skip them — no lens reviews them — and list them in the report's Files Checked
      as `skipped (data/asset)`. Bucketing is filename-based throughout: no file is ever opened to
      classify it. Collection stays extension-blind — never pre-filter by extension at the
      `find`/git stage; every file under the target must reach bucketing, or the skipped-files
      listing silently loses its rows.
- [ ] Resolve the gate commands (below)

**Argument disambiguation:** if an argument is given:

1. If it contains `..` or `...` → commit range immediately (skip `git rev-parse`)
2. Otherwise try `git rev-parse --verify <arg> 2>/dev/null`. If it succeeds → single commit-ref
   mode. If it fails → path mode.

| Source                         | Method                                                                        |
| ------------------------------ | ----------------------------------------------------------------------------- |
| Path argument (specific file)  | Use directly — user's explicit choice, gitignore not applied                  |
| Path argument (directory/glob) | Expand files, then filter gitignored: `git check-ignore --stdin < <filelist>` |
| Commit ref (single)            | `git diff --name-only <ref>~1 <ref>`                                          |
| Commit range (`a..b`)          | `git diff --name-only <from>..<to>`                                           |
| No argument                    | Union of all sources below (deduplicated)                                     |

**No-argument file collection** — always run all four, combine and deduplicate:

1. `git diff --name-only --diff-filter=d @{push}` — committed but not yet pushed (skip if `@{push}`
   fails — no upstream)
2. `git diff --name-only --diff-filter=d` — unstaged working-tree changes
3. `git diff --cached --name-only --diff-filter=d` — staged changes
4. `git ls-files --others --exclude-standard` — untracked, non-gitignored files

`--diff-filter=d` excludes deleted files everywhere: a deleted file has no content to review and
would abort the snapshot. Commit-ref and range modes take the same flag.

If no target files are found (empty diff and no path argument), report "No changes detected" and
stop.

**Gate commands** — resolve both halves and record them for steps 2, 4, 5, and 6:

- **Checkers** (linter + typechecker): look in `package.json` scripts (`lint`, `typecheck`,
  `check`), `lefthook.yml` (TypeScript projects), `.pre-commit-config.yaml` →
  `prek run --files
  <targets>` (never assume the `pre-commit` command exists),
  `Makefile`/`justfile` targets, `pyproject.toml` tool config (ruff, mypy).
- **Tests**: the project's test runner (`package.json` test script, pytest, busted, `swift test`,
  …). Intermediate gates (steps 2, 4, 5) may scope the test run to the target files where the runner
  supports file arguments; the exit gate (step 6) never scopes. Scope is decided here, once, before
  any gate runs — a red gate is never answered by re-running narrower.
- A project with no test suite gates on checkers alone; a project with no checkers gates on tests
  alone. Either absence is stated in the report — never silently treated as green-by-default on both
  halves. Neither half existing → skip gates, report "no gate commands found", review-only run.
- Resolve `<scratchpad>`: the session's scratchpad directory when the harness provides one,
  otherwise `$(mktemp -d)`. Record the path alongside the gate commands — every gate capture and
  snapshot below writes into it.

→ **TaskUpdate** task 1 to `completed`. **TaskUpdate** task 2 to `in_progress`.

---

### Step 2: Entry Gate

Run the gate script — it runs both halves, captures everything, and prints the verdict. Never re-run
to re-filter; the captures hold the full output:

```bash
node ${CLAUDE_SKILL_DIR}/scripts/gate.ts <scratchpad> entry "<checker command>" "<test command>"
```

Pass `""` for an absent half — the script reports it as SKIPPED and gates on the other alone.

- **Red (either half fails):** report status 🚫 **BLOCKED** with the failing output, jump to step 7.
  No review happens on a broken tree — reviewing it wastes the fan-out; editing it makes it worse.
  No severity judgment: a failure that looks trivial, stale, or obviously caused by the user's own
  diff is still red — that judgment belongs to the user, after BLOCKED is reported.
- **Green:** proceed. Pass NOTHING from the gate to the reviewers — a green gate can only say
  "everything passed"; there is no payload worth forwarding.

→ **TaskUpdate** task 2 to `completed`. **TaskUpdate** task 3 to `in_progress`.

---

### Step 3: Review — all lenses in parallel, one pass

Capture the review diff now (re-run the step 1 collection commands; in commit-ref/range mode use the
ref diff). Nothing edits between here and triage, so this diff stays current for every lens.
**Path-argument mode has no diff** — scope is `full`, so skip capture entirely; prompts carry the
file list and scope only. Capturing a diff means `git diff` output, never reading files.

**Launch all applicable lenses in a single message** — one **Agent** tool call per lens. Every lens
is a typed agent: **never set a model on any dispatch — each agent defines its own.**

Project CLAUDE.md conventions need no lens of their own: the harness injects the project's CLAUDE.md
into every subagent, and the reviewers' hub skills make its imperative conventions citeable rules. A
convention violation arrives as an ordinary `vet-*` finding.

**Checklist reviewers** — one per non-empty bucket from step 1:

- `subagent_type: vet-code` on the code files
- `subagent_type: vet-test` on the test files
- `subagent_type: vet-doc` on the doc files
- Prompt each:
  `"Review these files.\n\nFiles: [bucket file list]\n\nDiff:\n[review diff]\n\nScope: [full if
  path-argument mode, changed otherwise]"`
- Each loads its own hub and language leaves and returns `### Finding N` blocks. Do not name a skill
  in the prompt. `vet-doc` routes CHANGELOG.md to `write-changelog` rules on its own.
- `vet-skill` is not part of preflight — no bucket feeds it.

**Comment lens** (when code or test files exist) — comments in both buckets, one dispatch:

- `subagent_type: vet-comments`
- Prompt:
  `"Review these files.\n\nFiles: [code + test file list]\n\nDiff:\n[review diff]\n\nScope: [full
  if path-argument mode, changed otherwise]"`
- It resolves its own language skills per file and emits `### Finding N` blocks with Impact tags
  like every other lens. Its Skills/Exports preamble is its completeness proof — read past it;
  triage collects only the finding blocks.

**Bug Scanner** (when code files exist)

- `subagent_type: bug-scanner`
- Prompt:
  `"Review these files for runtime correctness bugs.\n\nFiles: [code file list]\n\nDiff:\n[review
  diff]\n\nScope: [full if path-argument mode, changed otherwise]"`

**Distill lens** (when code or test files exist) — read-only; it emits findings, it does not edit.
Silent unrecorded edits become countable, scoreable, gated findings instead.

- `subagent_type: distill-scanner` — its tool set has no Edit, so read-only is structural, not a
  prompt promise.
- Prompt:
  `"Review these files for distillation opportunities.\n\nFiles: [code + test file
  list]\n\nDiff:\n[review diff]\n\nScope: [full if path-argument mode, changed otherwise]"`
- The agent loads `distill-code` itself and carries its own scoring rubric and impact enum. Do not
  name a skill in the prompt.

**Review scope by input mode:**

- **Path argument**: scope = `full` — review entire file(s)
- **Commit ref / range / no-argument**: scope = `changed` — flag only issues in changed lines

**Completion gate — every lens back, verified.** Keep a dispatch ledger from the launch results:
lens → task-id. Step 3 ends only when every ledger row has a received task-notification whose
task-id matches its row. Match notifications to ledger rows, never keep a running tally — "five
results seen" is how a fabricated or twice-fired notification closes the step early. A
task-notification is an incoming message from the harness; lens-result text you authored,
summarized, or predicted is not one — composing a pending lens's result is fabrication, and a triage
pass over it is corrupt. Before the TaskUpdate below, confirm the ledger with TaskList: every lens
task `completed` with its notification received. Still running → keep waiting; an auto-continuation
nudge is not evidence a lens finished, and elapsed time is not a signal this contract recognizes.
Errored, or `completed` with empty or unusable output → stop and surface it
(`rules/skill-loading.md`) — never triage a partial lens set. Notification lost but TaskList shows
`completed` → read that task's output file; never re-dispatch, never reconstruct.

→ **TaskUpdate** task 3 to `completed`. **TaskUpdate** task 4 to `in_progress`.

---

### Step 4: Triage and Fix

**Triage** — one orchestrator pass over every lens's output. Read `references/triage.md` now and
follow it exactly: discard score-0 false positives (its list), partition on score (≥ 75 → fix queue,
else report-only), rank Impact tags against its per-lens enum table, adjudicate qualifying 50s
through one `claim-reviewer` dispatch, and keep the per-agent tally it defines.

**Empty fix queue — checked after adjudication → mark tasks 4 and 5 `completed`, skip to step 6.**

**Snapshot** — before any edit, from the repo root (a manifest-aware file copy — never `git stash`;
`stash create` cannot include untracked files and untracked files are in scope):

```bash
node ${CLAUDE_SKILL_DIR}/scripts/snapshot.ts save <scratchpad>/preflight-snap-1 <target files>
```

**Fix** — group the fix queue into **file groups** and dispatch **one `code-mender` per group**,
never per finding — concurrent menders sharing a file race each other, and `code-mender` takes a
list by contract. A finding's edit targets are the files its Location line and fix text name.

**Group together** (one mender): findings sharing any edit-target file, merged transitively — a
shared-helper extraction naming three files welds all three, plus every other finding on any of
them, into one group. **Keep separate** (parallel menders): findings whose file sets are disjoint.
**Rule of thumb** (mirrors `tdd`'s batching rule): if two fixes touch any common file, one mender
owns both; split across parallel menders, a cross-file fix cannot land — each mender sees only its
own file, and the gate goes red on the seam. When in doubt, group: over-grouping only costs
parallelism; under-grouping ships a half-applied fix.

Most findings name one file, so most groups are one file. A mender carrying many findings is not
lower quality than many menders carrying one each; the group is the race-safe unit. Send all group
dispatches in a single parallel message. Per group, pass every finding for its files:

```text
Issue: [description from finding]
Location: [file_path:line_number from finding]
Severity: [high if the Impact tag ranks 1 or 2 in the enum table in references/triage.md, medium if it ranks 3 or 4]
Suggested fix: [reasoning from finding]

Issue: [next finding for this file]
...
```

Record the set of edited files for step 5.

**Gate** —
`node ${CLAUDE_SKILL_DIR}/scripts/gate.ts <scratchpad> fix "<checker command>" "<test command>"`.

Classification is the script's `FAILING:` line — it names the red sub-checks; the captures hold the
detail. The line parses npm-run-s output; on `FAILING: (unparsed — see captures)`, classify by
grepping the captures instead — same evidence, one extra step. Never re-run checks with different
flags to diagnose, never run the tools directly, and never read target files — grep the captures
when the summary needs support, nothing more. The only decision here is which red-gate branch
applies.

- **Red:** read `references/red-gate.md` now and follow it exactly — the formatting-alone branch,
  one repair attempt, then the three-option restore decision (snapshot `preflight-snap-1`).
- **Green:** proceed.

→ **TaskUpdate** task 4 to `completed`. **TaskUpdate** task 5 to `in_progress`.

---

### Step 5: Post-Fix Scan and Verification

The step 3 bug scan only ever saw pre-fix code. Menders can introduce bugs — this is the pass that
sees the post-fix code. Style re-violations from a mender are not worth re-running the full lens
fan-out for, so this is `bug-scanner` only.

- `subagent_type: bug-scanner`, scoped to the files step 4 edited, with a fresh diff:
  `git diff -- <edited files>`. An untracked edited file has no diff — pass its name and let the
  scanner read it in full; never `cat` it into your own context.
- Prompt as in step 3, scope `changed`.

**If it returns findings ≥ 75:** one corrective round, then stop fixing regardless.

1. Snapshot the edited files:
   `node ${CLAUDE_SKILL_DIR}/scripts/snapshot.ts save <scratchpad>/preflight-snap-2 <edited files>`
2. One `code-mender` per file group (step 4's grouping rule), in parallel, same format as step 4
3. Gate:
   `node ${CLAUDE_SKILL_DIR}/scripts/gate.ts <scratchpad> corrective "<checker command>" "<test command>"`
   — on red, `references/red-gate.md` again, with `preflight-snap-2` as the snapshot. The gate's
   single repair attempt is gate machinery, not a round — the round cap counts scan-driven fix
   rounds.
4. **Scan the corrective edits** — dispatch `bug-scanner` once more, scoped to the files the
   corrective menders touched, with a fresh diff. Its findings — at any score — are report-only by
   the round cap: they join the Post-Fix Bugs (unresolved) table, never a fix queue. No snapshot or
   gate follows; a scan that cannot trigger edits needs neither. This is not a third round — the cap
   counts edit rounds, and a read-only scan edits nothing. Without it, the corrective menders' code
   would be the only code in the pipeline no reviewer ever reads.

Anything found after the corrective round is a report, not another iteration — including bugs you
notice yourself while reading a mender's report. The cap counts edit rounds, not who spotted the
issue, and a round done "properly" with snapshot and gate is still a third round. Findings < 75 join
the report-only queue.

**Verify the fix claims** — every mender report asserts issues were resolved; the gates only proved
nothing broke, and the scans only hunted new bugs. Read `references/verification.md` now and follow
it exactly: one `claim-reviewer` dispatch covering every qualifying applied fix from both rounds,
verdict routing into Verification Findings and Issues Reported, and the tally adjustment.
Verification is report-only — it never triggers a re-fix.

→ **TaskUpdate** task 5 to `completed`. **TaskUpdate** task 6 to `in_progress`.

---

### Step 6: Exit Gate

Run the **full suite, whole project** — checkers and tests, never scoped to the target files. This
catches breakage in callers outside the diff.

```bash
node ${CLAUDE_SKILL_DIR}/scripts/gate.ts <scratchpad> exit "<checker command>" "<full test command>"
```

- **Red:** report status 🚫 **GROUNDED** with the failing output and the list of files preflight
  changed (the fixes remain in the tree — say so explicitly), jump to step 7. A failure that looks
  environmental, pre-existing, or unrelated to the diff is still red — never downgrade GROUNDED
  based on your own read of relatedness.
- **Green:** proceed.

→ **TaskUpdate** task 6 to `completed`. **TaskUpdate** task 7 to `in_progress`.

---

### Step 7: Summary Report

Generate the final report. This is your first results output since the start announcement — the step
transition lines carried none. Read `references/report.md` now and follow it exactly: the status
vocabulary and the full template. Omit empty sections.

→ **TaskUpdate** task 7 to `completed`. **All tasks must now show as completed.**

---

## Common Mistakes

Each step states its own counters inline; triage and verification mistakes live in their reference
files. Only rules not stated elsewhere appear here:

- ❌ Auto-fixing linter issues → the gates run the project's configured tools; linter-catchable
  findings score 0
- ❌ Skipping the post-corrective scan because its findings can't be fixed → the report is the
  point; unscanned mender code is how bugs ship silently under a green gate
