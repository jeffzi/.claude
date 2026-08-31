# Round Lifecycle — Full Mechanics

The five steps in orchestration detail. SKILL.md states the sequence and the non-negotiables; this
file carries the per-step mechanics.

In standalone mode (SKILL.md **Standalone Mode**), that section's table substitutes every
harness-supplied input referenced below — scan areas, skill dispatch, ledger, `hardening-wip.md`,
the `claim-reviewer` pass — while the step sequence and its gates are unchanged.

## 1. Audit fan-out

Full scan by default: dispatch parallel read-only finder agents across every area in the harness's
**Scan Areas**; narrow only when the user names an area. Do NOT set model or effort on any dispatch
— the finder agents define their own. Prior rounds never exempt an area — "audited clean" describes
the code as it was then.

Every finder loads its methodology **as a skill, never a paraphrase** — a pasted gloss forks the
skill and goes stale the next time it changes. Each lens has its own agent, and they are not
interchangeable: correctness finders are `subagent_type: bug-scanner`; simplification finders are
`subagent_type: simplification-scanner`; the cross-file lens is `subagent_type: vet-codebase`
(self-contained — its rubric lives in the agent, with no separate scan skill). Each agent loads its
own skill as sole rubric and will override a prompt that tries to substitute the other lens.

The simplification lens is mandatory — it runs whether or not the harness mentions it, and a harness
may refine how its findings map to tasks but can never opt the round out of it. Roster shape: one
per-area finder per Scan Area (its own finder, or folded into that area's correctness finder), plus
**exactly one** global finder, always its own dispatch, plus **exactly one** cross-file finder
(`vet-codebase`) on the round's whole target — never one per area, because cross-area duplication is
what it exists to see. What each tier may claim is defined by `scan-simplification` itself, not
here.

Finders only _list_ — one line per claim, no edits. Every claim enters the same verify → classify →
plan → approval pipeline; a per-area candidate that a repo-wide grep later refutes at Verify is the
designed reconciliation, not wasted work.

## 2. Verify claim

A finder reports a _claim_, not a finding. Before it enters the plan: re-read the mechanism at the
line level and build a repro. Classify per the Finding Classification table in SKILL.md. False
claims are appended to the ledger, never silently dropped.

Claims are independent, so verification parallelizes. Group the claims by the module or file their
mechanism targets — claims on one mechanism verify together and share the reading. One group →
verify inline. Multiple groups → dispatch one **Agent** call per group, `subagent_type: "fork"`, all
in one parallel message. Each fork's prompt names its group's claims; the fork re-reads each
mechanism at the line level, builds the repro, and returns one line per claim —
`CLASS: <classification from the table> — <mechanism confirmed or disproof>`. Forks never write the
ledger, the plan, or any project file — repro scratch goes to a temp directory, and the parent alone
records the results: refuted claims to the ledger, the rest into the plan's classification.
Sequential verification of a multi-group claim set is the bottleneck this step exists to avoid.

## 3. Write plan

Load `Skill(write-plan)`; author the plan **once**, writing it **directly to
`<repo-root>/.planning/hardening-wip.md`** — a normal write, done **before entering plan mode**, so
plan mode never has to permit it and the fixed path is resumable from a later session the moment it
lands. The Context section carries the classified findings (refuted ones go to the ledger instead).
If the harness defines a **Diff Harness**, Task 0 is its baseline-snapshot step; projects whose
per-task gate is self-contained (just run the test suite) have no Task 0. Each task states its own
gate; behavior tasks say "Implementation: Use `/tdd`."

Then **verify the plan**: dispatch `claim-reviewer` (`subagent_type: claim-reviewer`, do NOT set
model — the agent defines its own) over its classified findings — each Bug / Landmine / DRY /
Docs-drift entry is a claim carrying a `file:line`. A finding the reviewer returns as **Refuted** or
**Unsubstantiated** goes back through step 2 exactly once: re-confirmed → it stays; genuinely false
→ ledger; still contested after that single pass → it stays in the plan marked **contested**, with
both reads, for the user to rule on at the approval gate. Never loop further; never drop it
silently.

The plan now lives on disk at its resume path; there is no separate copy step.

## 4. Approval gate

Enter plan mode, write the plan from `<repo-root>/.planning/hardening-wip.md` into the designated
plan-mode file, and use `ExitPlanMode` to present it. The user decides which tasks execute, in what
order, and which are cut. (The canonical no-execution-before-approval rule is the first Bright Line
— plan mode enforces it as a hard block: no edit, baseline, or commit runs until approval.) On
approval you leave plan mode, so updating `<repo-root>/.planning/hardening-wip.md` to reflect any
cuts or reordering is a normal write again — do it so the executed plan matches the approved one
byte-for-byte.

## 5. Execute

Tasks execute lowest → highest risk. Each task's work is fully committed before the next task
begins: a direct-edit task commits once; a `/tdd` task commits per tdd's own flow (a
tests-then-implementation pair per cycle, plus a refactor commit) — either way the task is a
contiguous commit range, so rollback and blame stay per-task. Load skills per the harness's **Skill
Dispatch** table for each area touched.

Run the harness's per-task gate **as an opaque command block** — this skill does not know whether
that block runs the test suite or build-plus-diff-plus-tests; it runs whatever the harness defines —
on the task's final working tree, before the commit that closes the task. Mid-task commits from
`/tdd` cycles follow tdd's implement → verify → commit order; when the gate block is exactly the
cycle's own verification commands, one run per commit point serves both skills — never run the same
suite twice on the same tree. A red gate is a failed task contract: fix it inside the task's commit
range or revert the range (with the user's say-so) — never start the next task over a red gate.
After the last task's gate is green and its closing commit lands, run the harness's
**Round-Completion Gate** if it defines one, then delete the working plan.
