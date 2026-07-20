---
name: harden
description: >
  Use when running a hardening round on a project — auditing for bugs and verified duplication and
  driving the fixes through a per-task gate — or when planning or executing a refactor that must
  leave behavior (or generated output) provably unchanged. Also use when deciding whether a diff is
  acceptable, or when triaging an audit finding (verified bug vs. landmine vs. refuted claim).
  Triggers: "hardening round", "audit bugs", "DRY pass", "zero-diff refactor", "is diff acceptable",
  finder agent reporting dead code or a suspected bug.
argument-hint: "[optional area]"
effort: high
---

# Hardening Round

A hardening round is a three-stage cycle: **audit fan-out → classified plan → gated execution**.

**Foundational principle: violating the letter of the gate is violating its spirit.** "Unchanged"
means unchanged, not "semantically equivalent."

## Artifacts and Cross-Round Memory

- **`.planning/hardening-ledger.md`** — the only kept artifact and the only cross-round memory: a
  single list of refuted claims, recorded at the **mechanism level with no line numbers** (line
  references rot on the next refactor; the mechanism that disproves a claim stays checkable). Read
  only the ledger before auditing. It de-duplicates _claims_ during verification; it never exempts
  an _area_ from a scan.
- **A ledger entry is trusted only while its disproof holds.** Before skipping a re-reported claim,
  re-check the recorded mechanism (e.g. "not dead — reached via the X emission path": confirm that
  path still exists). If the mechanism no longer holds, delete the entry and verify the claim afresh
  — refutations decay as code changes, exactly the way "audited clean" notes do.
- **`.planning/hardening-wip.md`** — the durable plan file, authored **directly** at step 3 (before
  entering plan mode, so the write is never blocked) and refreshed at step 4 if the user cuts or
  reorders at the gate, so the executed plan matches the approved one byte-for-byte. It is the
  cross-session resume point; the designated plan-mode file is session-scoped and undiscoverable
  from a later session. Resuming it never carries approval — the first Bright Line still forces a
  re-present. It is the round's execution reference and the cross-session resume point. A single
  reused, disposable filename, **not** a numbered series, never retained past the round, never read
  by a future round. Delete it when the round closes.

## Project Harness Lookup

This skill owns the methodology; the project supplies the tooling. Before anything else:

1. Find the repo root: `git rev-parse --show-toplevel`. If this fails (not a git repository), STOP
   and report: **"harden requires a git repository — the ledger, baselines, and diffs are all
   repo-relative."**
2. Read `<repo-root>/.claude/harden.md`. If it is missing, STOP and report: **"No hardening harness
   found at `.claude/harden.md` — create one following
   `~/.claude/docs/templates/harden-harness.md`."**
3. Confirm both finder skills are invocable: `scan-bug` and `scan-simplification`. If either is
   unavailable, STOP and name the missing one — a round without its correctness rubric or
   simplification lens is incomplete, not lean.

The harness defines this project's **Scan Areas**, **Skill Dispatch**, **Domain Doctrines**, and
optionally a **Diff Harness** (baseline snapshot + per-task gate, for projects with compiled or
generated output) and a **Round-Completion Gate**. This lookup is the only coupling point between
the general methodology and project configuration: everything project-specific is read from the
harness at runtime; nothing project-specific belongs in this skill.

## When NOT to Use

- Single bug with an unknown root cause → `/fix`
- New feature work → `Skill(tdd)`
- Performance work → profile first; hardening rounds are perf-neutral by construction

## Round Lifecycle

**Steps 1–4 are mandatory and sequential.** No step may be skipped or reordered. Step 5 (execution)
is unreachable without a user-approved plan.

1. **Audit fan-out.** Full scan by default: dispatch parallel read-only finder agents across every
   area in the harness's **Scan Areas**; narrow only when the user names an area. Prior rounds never
   exempt an area — "audited clean" describes the code as it was then.

   Every finder loads its methodology **as a skill, never a paraphrase**: the dispatched prompt
   instructs the sub-agent to invoke `Skill(scan-bug)` (correctness rubric) or
   `Skill(scan-simplification)` (simplification lens) and work from the live source. A pasted gloss
   forks the skill and goes stale the next time it changes. Dispatch with an agent type that can
   call `Skill` (e.g. `bug-scanner`) — on a Read/Glob/Grep-only finder the load silently no-ops.

   The fan-out always includes the **simplification lens** alongside the correctness finders. It is
   mandatory: it runs whether or not the harness mentions it, and a harness may refine how its
   findings map to tasks but can never opt the round out of it. It runs in two tiers:

   - **Per-area** — one per Scan Area; its own finder, or folded into that area's correctness
     finder. Flags what one slice can show; it never asserts a repo-wide fact.
   - **Global** — exactly one, always its own finder; the only tier with whole-caller-graph
     visibility. Owns what no slice can see: dead code and single-use abstractions whose lone caller
     sits in another area.

   Finders only _list_ — one line per claim, no edits. Every claim enters the same verify → classify
   → plan → approval pipeline; a per-area candidate that a repo-wide grep later refutes at Verify is
   the designed reconciliation, not wasted work.

2. **Verify claim.** A finder reports a _claim_, not a finding. Before it enters the plan: re-read
   the mechanism at the line level and build a repro. Classify per the table below. False claims are
   appended to the ledger, never silently dropped.

3. **Write plan.** Load `Skill(write-plan)`; author the plan **once**, writing it **directly to
   `.planning/hardening-wip.md`** — a normal write, done **before entering plan mode**, so plan mode
   never has to permit it and the fixed path is resumable from a later session the moment it lands.
   The Context section carries the classified findings (refuted ones go to the ledger instead). If
   the harness defines a **Diff Harness**, Task 0 is its baseline-snapshot step; projects whose
   per-task gate is self-contained (just run the test suite) have no Task 0. Each task states its
   own gate; behavior tasks say "Implementation: Use `/tdd`."

   Then **verify the plan**: dispatch `claim-reviewer` (`subagent_type: claim-reviewer`, no model
   override) over its classified findings — each Bug / Landmine / DRY / Docs-drift entry is a claim
   carrying a `file:line`. A finding the reviewer returns as **Refuted** or **Unsubstantiated** goes
   back through step 2 exactly once: re-confirmed → it stays; genuinely false → ledger; still
   contested after that single pass → it stays in the plan marked **contested**, with both reads,
   for the user to rule on at the approval gate. Never loop further; never drop it silently.

   The plan now lives on disk at its resume path; there is no separate copy step. Stay out of plan
   mode until the gate — nothing is authored inside it, so plan mode never has to permit a write.

4. **Approval gate.** Now enter plan mode, write the plan from `.planning/hardening-wip.md` into the
   designated plan-mode file, and use `ExitPlanMode` to present it. The user decides which tasks
   execute, in what order, and which are cut. (The canonical no-execution-before-approval rule is
   the first Bright Line — plan mode enforces it as a hard block: no edit, baseline, or commit runs
   until approval.) On approval you leave plan mode, so updating `.planning/hardening-wip.md` to
   reflect any cuts or reordering is a normal write again — do it so the executed plan matches the
   approved one byte-for-byte.

5. **Execute.** Per-task commits, lowest → highest risk, so rollback is trivial. Load skills per the
   harness's **Skill Dispatch** table for each area touched. After each task, run the harness's
   per-task gate **as an opaque command block** — this skill does not know whether that block runs
   the test suite or build-plus-diff-plus-tests; it runs whatever the harness defines and requires
   it to pass before the task is committed. After the last task is committed, run the harness's
   **Round-Completion Gate** if it defines one, then delete the working plan.

## Finding Classification

| Class             | Definition                                                                                                       | Plan disposition                                                                                                                           |
| ----------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **Bug**           | Wrong output or crash; mechanism verified at line level, repro shape known                                       | Own task, `/tdd`                                                                                                                           |
| **Landmine**      | Two sources that must agree disagree; unreachable today by convention only                                       | Own task; write a comparator test first — it must fail against current code before the fix                                                 |
| **Smell**         | Same class as a past bug, harmless today                                                                         | Surface with a fix-vs-document recommendation — the user decides; silent status quo is not an option                                       |
| **DRY**           | Verified duplication across files                                                                                | No-new-tests task, verified by the per-task gate                                                                                           |
| **Docs drift**    | Docs disagree with source                                                                                        | `docs:` task; verify signatures against source, never from memory                                                                          |
| **Audited clean** | Checked and sound                                                                                                | Record in the round's Context ("record only") — within-round coverage tracking, **not** cross-round memory; never read it in a later round |
| **Refuted**       | Claim is false                                                                                                   | Append to the ledger — this stops round N+1 re-chasing it while the disproof holds                                                         |
| **Declined**      | Change is _possible_ but unwise (order-sensitive, intentionally divergent, theoretical-only risk vs. real churn) | Record in Context as "reviewed, declined" with the reason — do not implement                                                               |

A confirmed simplification finding routes by the diff its fix produces, not by which lens or tag
reported it: a fix that leaves output byte-identical (dead-code deletion, duplication merge) is a
**DRY** task; a fix that deliberately changes output (replacing custom code with stdlib or a native
platform feature, removing a speculative abstraction) is a **deliberate-output-change** task
confined to the named call sites.

Refuted ≠ Declined: a refuted finding is _false_; a declined one is true but not worth the cost. A
refactor that cannot reach an empty diff is **declined** (or surfaced), never "refuted."

## Diff Harness

This section applies **only when the harness defines a Diff Harness** — projects with compiled or
generated output (codegen, transpilation, a build step whose bytes must stay identical). Pure
interpreted codebases skip it; their per-task gate is just the test suite.

The general framework is fixed; the commands come from the harness:

- **Task 0 (baseline snapshot), always first.** Run the harness's baseline-snapshot commands. Always
  from a clean working tree — commit first; uncommitted edits leak into the baseline.
- **Per-task gate.** Run the harness's per-task gate commands. These rebuild, diff against the
  baseline, and run the relevant tests. The diff gates the output; the tests gate behavior the diff
  cannot see (helper renames, fixture imports, anything structural). Catching a regression only at a
  round-end gate loses per-task attribution.
- **Re-baseline after every accepted non-empty diff.** Once a task whose diff was accepted (a bug
  fix or a deliberate output change) is committed, re-run the **full** Task 0 block from the
  committed HEAD. Otherwise every later task's gate re-reports the accepted hunks and forces
  hunk-by-hunk eyeballing — the judgment the gate exists to replace. Re-cutting from a committed
  HEAD is always safe; the same recovery applies if the baseline is wiped mid-round.

### Diff Gates by Task Type

| Task type                | Acceptable diff                                                                           |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| DRY / pure refactor      | **Empty.** Any non-empty diff fails the task.                                             |
| Bug fix                  | Confined to the lines implementing the fix — inspect every hunk.                          |
| Deliberate output change | Confined to the named functions / call sites; verify coupled properties move in lockstep. |

The harness's **Diff Acceptability** section may add project-specific rules on top of this table
(e.g. "a shifted generated identifier is a failure" for codegen projects).

## Bright Lines

- **No execution before plan approval.** The plan must pass through `ExitPlanMode` and receive an
  explicit go-ahead in the _current_ session before any TDD cycle, code edit, or baseline snapshot
  runs. Reading an existing plan file, loading skills, or a plan written in a prior session does not
  count — a plan from an earlier conversation carries no standing approval; re-present it and wait
  for the go-ahead.
- **"Tests pass" is not the gate when the harness defines a diff gate.** A suite that asserts
  decisions or structure is blind to ordering and naming churn by design. Green tests plus a dirty
  diff is a failed task.
- **If the required diff cannot be reached, surface or revert.** There is no "accept the cosmetic
  part." Reading a diff and deciding it is "probably fine" is exactly the judgment the gate exists
  to replace.
- **Never skip the harness because a change "can't affect output."** Prove it by running the gate —
  it is cheap.

## Rationalizations That Mean You're About to Fail

| Excuse                                                                                     | Reality                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| "Tests are green; a real bug would've been caught"                                         | The suite can be gate-blind by design. Green tests + dirty diff = failed task.                                                                                                                                                       |
| "Snapshot drift is expected when refactoring"                                              | The task's contract was a clean diff. Drift means the task failed its contract, not that the baseline aged.                                                                                                                          |
| "The finder says it's dead code — schedule deletion"                                       | A finder reports _claims_. Verify the mechanism — grep every emission path, not just imports — before deleting anything.                                                                                                             |
| "I refuted the claim, nothing to record"                                                   | Append the disproof to the ledger. Unrecorded refutations get re-investigated next round at full price.                                                                                                                              |
| "I'll cite file:line so the refutation is precise"                                         | Line numbers rot on the next refactor — staleness is why plans are not cross-round memory. Record the _mechanism_ that disproves it, never the location.                                                                             |
| "The ledger already refuted this — skip it"                                                | Only while the recorded disproof still holds. Re-check the mechanism first; a refutation decays the moment the code it cites changes.                                                                                                |
| "Round N already audited that area — skip it"                                              | "Audited clean" describes the code as it was then. Fan-out is the cheap stage; scan everything unless the user scoped the round.                                                                                                     |
| "Bug and DRY finders cover the fan-out — the simplification lens is optional"              | The simplification lens is mandatory and catches what correctness finders miss (stdlib / native / over-engineering). A roster without it is incomplete, not lean — STOP and add it.                                                  |
| "I'll inline the finder's rubric in the prompt — same content, one fewer skill load"       | A skill is the source of truth; a pasted gloss forks it and goes stale the next time `scan-bug` or `scan-simplification` is edited. The finder prompt must tell the sub-agent to invoke the skill, not carry a copy of its contents. |
| "The tasks are obvious — I'll skip straight to TDD"                                        | The approval step is where the user decides what to execute, reorder, or cut. Skipping it removes their agency.                                                                                                                      |
| "The plan already exists — I'll just start executing"                                      | A plan from a prior session was never approved in this one. Enter plan mode, present it, wait for the go-ahead.                                                                                                                      |
| "I'll add the finder's claims to the plan unverified"                                      | Plan tasks would chase phantoms; repro-first is cheaper. Verify before it enters the plan.                                                                                                                                           |
| "The reviewer and my re-verification disagree — one more verification pass will settle it" | One re-verification per finding, then it goes to the user marked contested. Extra passes launder uncertainty into false confidence.                                                                                                  |
| "DRY task — I'll write tests for the extracted code"                                       | DRY tasks are gated by the existing suite plus the diff. New tests belong to behavior tasks.                                                                                                                                         |
| "I'll run the diff gate once at the end of the round"                                      | A dirty hunk can then no longer be attributed to a task; rollback granularity is lost. Gate per task.                                                                                                                                |
| "I'll condense the plan for presentation"                                                  | The presented plan and the executed plan are the same document. Author once, directly in `.planning/hardening-wip.md`; the plan-mode file and the presentation are copies of it, never a re-authored summary.                        |
