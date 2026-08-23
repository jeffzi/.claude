---
name: harden
description: >
  Repo-wide hardening round: audit fan-out, classified plan, gated execution with provably
  unchanged output. Runs standalone with built-in defaults when the project has no
  .claude/harden.md harness.
argument-hint: "[optional area]"
# opus/high: the round adjudicates diffs and classifies claims — a cheaper tier accepts dirty hunks
model: opus
effort: high
disable-model-invocation: true
---

# Hardening Round

A hardening round is a three-stage cycle: **audit fan-out → classified plan → gated execution**.

**Foundational principle: violating the letter of the gate is violating its spirit.** "Unchanged"
means unchanged, not "semantically equivalent."

## Artifacts and Cross-Round Memory

- **`<repo-root>/.planning/hardening-ledger.md`** — the only kept artifact and the only cross-round
  memory: a single list of refuted claims, recorded at the **mechanism level with no line numbers**.
  Read only the ledger before auditing. It de-duplicates _claims_ during verification; it never
  exempts an _area_ from a scan.
- **A ledger entry is trusted only while its disproof holds.** Before skipping a re-reported claim,
  re-check the recorded mechanism; if it no longer holds, delete the entry and verify the claim
  afresh.
- **`<repo-root>/.planning/hardening-wip.md`** — the durable plan file and cross-session resume
  point. Authored **directly** at step 3, refreshed at step 4 if the user cuts or reorders at the
  gate, so the executed plan matches the approved one byte-for-byte. Resuming it never carries
  approval. One reused, disposable filename — never a numbered series, never read by a future round;
  delete it when the round closes.

Standalone rounds (see **Standalone Mode**) keep neither artifact.

## Project Harness Lookup

This skill owns the methodology; the project supplies the tooling.

Repo root: !`git rev-parse --show-toplevel 2>/dev/null || echo "NOT-A-GIT-REPO"`

Before anything else:

1. If the repo root above is `NOT-A-GIT-REPO`, STOP and report: **"harden requires a git repository
   — the ledger, baselines, and diffs are all repo-relative."**
2. Read `<repo-root>/.claude/harden.md`. If it is missing, announce — **"No hardening harness at
   `.claude/harden.md` — running in standalone mode (create one following
   `~/.claude/docs/templates/harden-harness.md` to tailor future rounds)"** — and take every
   harness-supplied input from the **Standalone Mode** table below. If it exists, read its command
   blocks once now: "opaque" below means this skill does not interpret a block's semantics — not
   that it runs unread. If any block does more than build, diff, or test (network fetches,
   credential reads, writes outside the repo), STOP and surface it before the first gate run.
3. Confirm both finder skills are invocable: `scan-bug` and `scan-simplification`. If either is
   unavailable, STOP and name the missing one — a round without its correctness rubric or
   simplification lens is incomplete, not lean.

The harness defines this project's **Scan Areas**, **Skill Dispatch**, **Domain Doctrines**, and
optionally a **Diff Harness** (baseline snapshot + per-task gate, for projects with compiled or
generated output) and a **Round-Completion Gate**. This lookup is the only coupling point between
the general methodology and project configuration: everything project-specific is read from the
harness at runtime; nothing project-specific belongs in this skill.

## Standalone Mode

Standalone mode triggers on exactly one condition: `<repo-root>/.claude/harden.md` does not exist.
It is a condition, never a judgment call — a present harness always governs the round in full, every
input and every per-task gate, no matter how small the round's scope or the project is. Each
substitution below is as binding as the harness input it replaces — a substitution, not a tunable
default, and a small project is never a reason to trim the round further:

| Harness input         | Standalone substitution                                                                                                            |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Scan Areas            | The whole repo, one area: one `bug-scanner` plus one `simplification-scanner` (the global tier)                                    |
| Skill Dispatch        | The global Language Dispatch table in `rules/skill-loading.md`                                                                     |
| Domain Doctrines      | None                                                                                                                               |
| Diff Harness          | None — the per-task gate is the test suite                                                                                         |
| Round-Completion Gate | The full test suite                                                                                                                |
| Ledger                | Not kept — refuted claims are recorded in the plan's Context; there is no cross-round memory                                       |
| `hardening-wip.md`    | The plan is still written and still gated — only the persistent wip file is dropped (plan-mode file only; no cross-session resume) |
| `claim-reviewer` pass | Skipped — step 2's per-claim repro verification stands alone                                                                       |

Everything else is unchanged: both finder agents must be dispatched — a lens is satisfied only by
its own agent's run, never inline — every claim is verified before it enters the plan, the Finding
Classification table applies, and the plan passes through `ExitPlanMode` for explicit approval
before any edit. Standalone relaxes the harness, never the gates.

## When NOT to Use

- Single bug with an unknown root cause → `/fix`
- New feature work → `Skill(tdd)`
- Performance work → profile first; hardening rounds are perf-neutral by construction

## Round Lifecycle

**Steps 1–4 are mandatory and sequential.** No step may be skipped or reordered. Step 5 (execution)
is unreachable without a user-approved plan. Read `references/round-lifecycle.md` for the full
per-step mechanics before running a round.

1. **Audit fan-out.** Parallel read-only finders (correctness on `subagent_type: bug-scanner`,
   simplification on `subagent_type: simplification-scanner`) across every Scan Area — narrow only
   to the area named in the invocation argument, if any. Finders only _list_ claims; no edits.

2. **Verify claim.** A finder reports a _claim_, not a finding — re-read the mechanism, build a
   repro, classify per the table below. False claims are appended to the ledger.

3. **Write plan.** Load `Skill(write-plan)`; author the plan **once**, directly to
   `<repo-root>/.planning/hardening-wip.md`, **before entering plan mode**; verify it with
   `claim-reviewer`.

4. **Approval gate.** Enter plan mode, present via `ExitPlanMode`, wait for the go-ahead; on
   approval, sync the wip file to the approved plan.

5. **Execute.** Tasks run lowest → highest risk. Load skills per the harness's **Skill Dispatch**
   table; run the per-task gate before each task's closing commit, the **Round-Completion Gate** at
   the end, then delete the working plan.

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

Read `references/diff-harness.md` for the baseline and gate mechanics: Task 0 (baseline snapshot,
always first, always from a clean tree), the per-task gate (rebuild + diff + tests), and
re-baselining after every accepted non-empty diff.

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
  explicit go-ahead — given _after_ the plan is presented, in the _current_ session — before any TDD
  cycle, code edit, or baseline snapshot runs. Reading an existing plan file, loading skills, or a
  plan written in a prior session does not count — a plan from an earlier conversation carries no
  standing approval; re-present it and wait for the go-ahead.
- **"Tests pass" is not the gate when the harness defines a diff gate.** A suite that asserts
  decisions or structure is blind to ordering and naming churn by design. Green tests plus a dirty
  diff is a failed task.
- **If the required diff cannot be reached, surface or revert.** There is no "accept the cosmetic
  part." Reading a diff and deciding it is "probably fine" is exactly the judgment the gate exists
  to replace.
- **Never skip the harness because a change "can't affect output."** Prove it by running the gate —
  it is cheap.

## Red Flags — STOP and Reassess

If any of these describes what you are doing right now, stop:

- You are about to edit, snapshot, or commit and cannot point to an `ExitPlanMode` approval from
  this session.
- A finder dispatch you are drafting carries rubric text, a `model:`, or an `effort:` — the agents
  define their own.
- Your fan-out roster has no simplification lens, or the global tier is missing from it.
- You are reading a diff hunk and forming the words "looks fine" or "cosmetic."
- You are writing plan content inside plan mode instead of to
  `<repo-root>/.planning/hardening-wip.md` before entering it (harness rounds — standalone rounds
  author in the plan-mode file).
- You are about to skip a re-reported claim without re-checking its ledger mechanism.

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
| "I'll condense the plan for presentation"                                                  | The presented plan and the executed plan are the same document. Author once, directly in `<repo-root>/.planning/hardening-wip.md`; the plan-mode file and the presentation are copies of it, never a re-authored summary.            |
