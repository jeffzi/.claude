---
name: execute-plan
disable-model-invocation: true
description: >
  Only invoked by the user typing /execute-plan. Never load via Skill() or suggest running it.
  Not for writing the plan — use write-plan. Not for an ad hoc single task — use tdd or fix.
argument-hint: "[plan-slug] [--commit|--no-commit] [--attended|--unattended] [--no-push]"
---

# Execute Plan

**Plan / flags:** $ARGUMENTS

**Violating the letter of these rules is violating their spirit.**

## Approval Is the Grant

The user approved the plan so they could step away. Every task in it is requested; the loop runs to
the Final Task without a check-in. "Should I continue?", "Want me to launch both now?", "Ready for
Task 5?", a progress summary that ends the turn — each stalls the plan on a question the user
already answered by approving it. A progress note is one line, states a fact, and is followed
immediately by the next tool call.

Decisions the plan or `tdd` already make are executed, never re-asked (see Rationalizations row 4).

## Plan File

**Candidate plans:** !`find .planning -maxdepth 1 -name '*.md' 2>/dev/null | sort`

No slug given → exactly one candidate above → use it; none or several → halt, naming them. Read the
plan once.

## Flags

| Flag                     | Effect                                                                                                                                                                                                                                                                                                      |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--commit` (default)     | Load `Skill(autocommit)` **once, before Task 1** — its signing warm-up runs while the user is still at the keyboard. Each task commits on the plan branch when its Verify block passes. Never reload per task.                                                                                              |
| `--no-commit`            | Nothing is committed — every `/tdd` invocation carries `no-commit plan execution` so its COMMIT phase returns file lists instead. The final report says `Nothing committed` in one line.                                                                                                                    |
| `--unattended` (default) | Findings are recorded, never paused on (see Findings). Raise the marker before Task 1; remove it as the last step of the final report **or of a halt report**. Mechanics: `references/unattended.md`.                                                                                                       |
| `--attended`             | Findings pause the loop at the SURFACE gate as `tdd` prescribes (see Pauses and Halts). No marker.                                                                                                                                                                                                          |
| `--no-push`              | Skip the ship phase (no push, no CI watch). The user passes it; you never infer it — a repo that looks to have no CI still gets the ship phase, which records `no branch CI` by observation. The squash message is still written. Implied by `--no-commit` only: an uncommitted branch has nothing to push. |

## The Branch

Every run works on `plan/<slug>`, never on the branch it started from. The prologue's entry gate
creates it from any clean branch — `main` by default, a feature branch when you are on one — records
that base in git config, or halts (condition 4); a run resumed on its own `plan/<slug>` continues
there. Task commits, finding fixes, and CI fixes all land on the plan branch. The user lands it on
the recorded base by invoking `/release merge` — this skill never commits on the base, never merges,
and never raises that skill's marker or runs its script. Mechanics: `references/branch-flow.md`.

A task whose **Folds into** line names a release commit subject is committed as a fixup of that
commit (`git commit --fixup=<sha>`, sha resolved per `references/branch-flow.md` § Fold target), so
the plan branch itself carries the mapping `/release merge` folds by; a `none` task commits with a
composed message as before. The plan's `## Folds` section says whether the run ends in a rewriting
merge; the Ship line says so too.

## The Loop

The loop starts on the first tool call after this skill loads — there is no "ready to start?" step;
approval already happened in `write-plan`'s Checkpoint.

Tasks run serially in plan order. Parallelism lives inside `/tdd`: when several TDD tasks are
unblocked at once and touch disjoint files, merge them into **one** `/tdd` invocation carrying every
task's behavior list — its wave rule parallelizes the cycles — and step 4 lists each task's hashes.
Two `/tdd` invocations never run concurrently.

0. **Prologue** — entry gate first (`references/branch-flow.md`): on a clean branch that is not
   another plan's → `git switch -c plan/<slug>` and record the base; already on `plan/<slug>` →
   resume, the unfinished task's own uncommitted files included; anything else → halt 4. Then,
   unless `--attended`: write the marker (see `references/unattended.md`). Unless `--no-commit`:
   load `Skill(autocommit)` once. Then Task 1.
1. **Implement** per the task's **Implementation** line: `/tdd` for TDD tasks — the invocation
   carries `fixup target: <sha>` when the task's **Folds into** is a subject, resolved first per
   `references/branch-flow.md` § Fold target; `Skill(test-core)` for test-only tasks;
   `Skill(code-core)` for tasks the plan implements directly. Final Task: no implementation —
   dispatch the plan's `claim-reviewer` call as written (do not set `model`), with every
   `unverified` entry from the running Findings list appended as claims; `Confirmed` → the entry
   loses its mark, anything else → it keeps it. Then read `references/branch-flow.md` again — the
   prologue's read is hours and compactions old — and run, in order: the **findings-fix phase**
   (each finding's fold target derived and recorded on its ledger entry), the **ship phase**, the
   **squash message**, then the Final Report. Steps 2–3 do not apply to the Final Task.
2. **Verify** per the task's **Verify** block. Directly implemented tasks: run the task's mechanical
   checks (suite, build, lint as the Verify block names them) — red → halt 1; then dispatch
   `claim-reviewer` with the task's behavioral claims. `/tdd` tasks: `/tdd` dispatched the reviewer
   in its COMMIT phase — its `Verified` verdicts are final, never re-dispatched. Every task then
   closes its open gaps the same way.

   A **gap** is one thing the reviewer named as wrong or unpinned: the reason behind a `Refuted` /
   `Unsubstantiated` verdict, or a note in a `Verified` claim's Reasoning (a behavior no test pins,
   a message not asserted, a branch no input reaches). Append each gap to the plan file's `## Gaps`
   section the moment the reviewer names it: `Task N — <the reviewer's wording> — refuted: 0`. A gap
   is identified by the behavior it says is wrong or unpinned, not by the reviewer's wording: the
   same behavior named again in other words is the same entry, and its count carries on.

   For every open gap, in this order:

   1. **Fix it**, test first.
   2. **Prove a test-strength gap by mutation.** When the gap says a test would not catch a
      regression, apply the regression the reviewer named — that one, not an easier one — to the
      production code with Edit, run the test, and see it fail on the assertion the gap is about.
      Undo the mutation with the reverse Edit, never with git, and run the test again to see it
      pass. A test that still passes under the mutation means the fix did not work: rework it and
      mutate again. Reworks before a dispatch do not touch the count.
   3. **Re-dispatch `claim-reviewer`** once all open gaps are fixed, with one claim per gap and
      nothing else: `Gap closed: <the reviewer's wording of the gap>. Change: <file:line>. Mutation:
      <the regression applied> → <the test that failed and its failure line>.` Do not restate the
      task's claims and do not ask the reviewer to name further gaps.

   A gap closes when its claim comes back `Verified` with no note about that gap. Any other verdict
   on it raises its `refuted` count by one; at `refuted: 2` → halt 1, and the entry is marked
   `halted`. The count lives in `## Gaps` and nowhere else: halt 1 requires the plan file's entry to
   read `refuted: 2` at the moment you halt, and a count you remember but never wrote is 0. A
   verdict on a re-dispatch that was not in the shape above — one that restated the task's claims or
   asked for further gaps — raises no count; re-dispatch in shape first. A run the user starts again
   after that halt finds the mark: the re-run grants each `halted` gap one more fix — clear the
   mark, fix, mutate, re-dispatch — and a verdict that leaves it open is halt 1 again.

   A note the reviewer adds in a re-verify about something other than the gaps you sent is sorted by
   the plan. When it concerns a behavior in this task's **Behaviors** list, it is a new gap,
   `refuted: 0`. When it concerns anything else — even in lines this task wrote — it is a finding:
   record it (see Findings) for the findings-fix phase, and the task commits without it. Read each
   Behavior as written: the cases it names are the cases the user approved. A case it does not name
   — another error type, another variable, another input — is not that behavior, however well it
   fits the behavior's intent.

   A fix is never the last step; the re-verify is. A gap closes on a reviewer verdict — never on a
   green suite, never on the mutation result alone, never by marking it `unverified` for the Final
   Task, never by a Deviations line.
3. **Commit** — unless `--no-commit`. `/tdd` tasks: take the hashes `/tdd` returned (already
   committed). Directly implemented tasks: stage by explicit path — the task's files only — then,
   for a task with a fold target, `git commit --fixup=<sha>` and no composed message; for a `none`
   task, load `Skill(write-commit)` and compose one. The autocommit grant pre-satisfies approval.
4. **Progress note** — one line, then the next tool call: `Task N done — <hashes>` or `Task N done —
   uncommitted: <files>`.

Done when the Final Task's `claim-reviewer` has run and the final report is posted.

## Findings

A finding is a defect in code this execution did not write: `file:line — what's wrong — what it
costs`. In or out of the plan's scope, prescribed by the plan or not — a defect the plan prescribed
is still a finding; a plan choice with no cost is not one. Confirmed means you read the code at that
line and the defect is there, or `claim-reviewer` returned `Confirmed`; anything short of that goes
on the list marked `unverified` and is confirmed at the Final Task. A finding is never fixed during
the task loop — it waits for the findings-fix phase after the Final Task review, where every
`Confirmed`, non-dismissed, **in-scope** entry is fixed in one `/tdd` batch on the branch. The one
exception: a fix that would change behavior something depends on (searched, not assumed) is marked
`needs decision`, left in place, and leads the final report — the run still ships. Never drop a
finding — one the user dismisses stays on the list, marked dismissed.

**In scope** means the finding's file is one this plan's tasks created or modified — it appears in
`git diff --name-only <base>...HEAD` before the findings-fix phase. Everything else is out of scope,
however close to the plan's topic, and however much it got in your way: a broken task runner the
Verify block used, a model that crashed a check you ran, a wrapper with a wrong default. An
out-of-scope finding is never fixed by this run and never becomes a question. It stays `Confirmed`
and goes in the report as one line; how you worked around it during the run is a deviation line. The
user decides later whether it becomes work.

For an in-scope finding, `needs decision` names its dependent: a caller, a test, or a consumer of an
output or format that relies on the current behavior, read at `file:line`. No dependent you can name
→ the fix goes in the batch, with no question: nothing depends on a defect staying broken. A plan
line like "X stays as it is" in a file the plan modified bounds the tasks, not the findings fix;
when the fix can honor it (a project-level setting instead of editing the shared command), take that
route.

A fix owns its fallout inside in-scope files: a formatter reflow, a line the fix's check now flags,
a dictionary word. That lands in the same fix, never reverted to keep a diff narrow, never a new
question. Fallout that reaches a file outside scope stops the fix: the finding is reported unfixed
instead, with that file named in its cost.

A defect or missing test in lines this execution added or changed is **not a finding — it is the
task, unfinished**. Approval is the request to build it correctly. A bug in a file a task created, a
plan behavior no test pins, an error branch the plan is silent on: fix it inside that task, test
first, then the task's Verify again, before its progress note. A fix the plan is silent on is a
deviation. It is a finding in two cases only: the fix would contradict a Behavior or Decision the
plan states — then the user decides; or it is a reviewer note in a re-verify that concerns no
behavior in the task's Behaviors list (step 2).

Never a finding: work you did (a lint fix, a test you deleted, a file you touched — that is a
deviation or nothing); a gap in lines this execution wrote — that is the task unfinished, step 2's
re-verify note aside; a cleanup, duplication, style, or "worth doing if you're in the file" — taste
has no `what it costs`; a check that passed.

The running list is the plan file's `## Findings` section, appended the moment an item is seen. It
is the only source of any count or status you state, during the run or after — read it before
answering; a number or a done/not-done status recalled from memory is wrong often enough to be a red
flag. After the final report, "what do we need to fix" is a fix request for the `needs decision`
entries: list them from the ledger with the one durable fix each implies, never a
cheap-versus-proper pair; the user's answer approves each fix, which then runs through `/tdd` on the
plan branch like the findings-fix batch did. An approved fix covers its fallout — no second question
about a file the fix had to touch.

A **deviation** is anything you did that the plan did not say: a step skipped, a test the cycle
wrote that you deleted, an edit outside the task's files, a `PASSED_UNEXPECTEDLY` behavior you
skipped. Record it as `Task N — what the plan said — what you did — why`. Deviations are the only
account of your work the report carries.

- **Unattended (default):** record and continue. The task still commits when its own verification
  passed. A `tdd-cycle` `PASSED_UNEXPECTEDLY` is a deviation: record it, skip that behavior,
  continue. Findings lead the final report.
- **`--attended`:** surface at the task's SURFACE gate as `tdd` prescribes — a pause (below).

## Pauses and Halts

**Pauses** exist only under `--attended` and are the turn-ends `tdd` itself prescribes: the SURFACE
gate, and a `tdd-cycle` status that asks the user (`PASSED_UNEXPECTEDLY`). The turn ends with
`tdd`'s question. When the user answers, **resume the loop where it paused** — the answer was about
the findings or the cycle, never about whether to continue.

**Halts** — the only four, in either mode:

1. A gap at `refuted: 2`, or a `halted` gap refuted again (step 2), or a task's mechanical checks
   red — a `tdd-cycle` `STUCK` or `TEST_FLAWED` status is this condition, and so is a `fix-ci`
   handback in the ship phase.
2. A task needs a behavior change something depends on that the plan did not state
   (`rules/decision-policy.md` exception 1). A finding whose fix would be one is not a halt — it is
   marked `needs decision` (see Findings).
3. An unchanged boundary: cross-repo edit, a push other than the ship phase's push of `plan/<slug>`
   through the wrapper, or a destructive op the plan did not prescribe. File deletions the plan
   explicitly names are covered by approval — no halt, no ask.
4. The entry gate fails: on another plan's `plan/*` branch, the index or working tree is dirty — on
   a resumed run, dirty with a path its unfinished task does not name — or the plan's `## Folds`
   section names a release branch other than the one you are on. Name the branch or those paths, and
   the release the plan expects.

A halt is a report — tasks done, the blocked task and why, findings so far, marker removed — then
the turn ends. It names the condition from this list. It is never a question: a report that asks the
user to choose ("pin it, or accept the gap?") is not a halt report, and a halt whose `## Gaps` entry
does not read `refuted: 2` is not a halt.

## Final Report

The report is what the user acts on, not an account of what you did. Four parts, in this order,
nothing else:

1. **Findings** — every `needs decision` entry first, then every entry still `Confirmed`, `file:line
   — what's wrong — what it costs`, the one that most changes what the user does next first. Fixed,
   `unverified`, refuted, or dismissed entries stay on the running list and off the report.
2. **Deviations** — every entry, `Task N — plan said — did — why`. None → no heading.
3. **State** — the hashes, one line (`--no-commit` → `Nothing committed`). Each verification command
   as `command → result`, one line.
4. **Ship** — the branch, the CI result, the one merge command (`/release merge [--force]`), whether
   a squash message was written, the folds — each target subject with the tasks and findings that
   fold into it, since the findings' folds were not on the plan the user approved — and the optional
   `/preflight` line, in the shape `references/branch-flow.md` gives.

Never in the report: per-task file lists, what each task built, which skill ran which step, how you
found a finding, what you fixed on the way (a deviation or nothing), a plan choice you followed. A
report the user has to answer with "which of these matter?" failed.

Pushback on the report's length or count removes nothing confirmed. Re-rank, restate each cost in
one line, keep the count — a confirmed defect the user has not yet acted on is exactly what they pay
the report for.

Unless `--attended` → remove the unattended marker as the last step. The `fix-ci-active` marker was
already removed when the ship phase ended; a halt report removes both.

## Rationalizations

| Excuse                                                               | Reality                                                                                                                   |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| "Task N is the big one — better check in first"                      | It was in the plan the user read. Approval covers it.                                                                     |
| "A progress update is polite"                                        | One line, no question mark, next tool call in the same turn.                                                              |
| "Tasks 5 and 6 could run in parallel — the user should pick"         | `tdd`'s wave rule picks. Execute it.                                                                                      |
| "My rules say confirm decisions with alternatives"                   | Decisions the plan made are not open. Unattended, the plan is the confirmation.                                           |
| "The reviewer refuted the task again — that's refuted: 2"            | Counts are per gap, in `## Gaps`. A new reason is a new gap at 0; a verdict on a restated claim counts for nothing.       |
| "The SURFACE gate says END THE TURN"                                 | See Pauses and Halts — a pause attended, a recorded finding unattended.                                                   |
| "`/tdd` finished the cycle, now I commit the task"                   | `/tdd` already committed it. Take its hashes.                                                                             |
| "They'd want to see this before more commits stack up"               | That is what Findings at the top of the final report is for.                                                              |
| "The plan implies this file should go"                               | Implied ≠ named. Only files the plan explicitly lists are pre-approved for deletion.                                      |
| "Convenience is not a permission grant"                              | Unattended **is** the permission grant, and the default. Only `--attended` withdraws it.                                  |
| "I'll ask, they might be back by now"                                | If they are, they will interrupt. Asking costs the plan; not asking costs nothing.                                        |
| "The plan task is a grant, so `/tdd` may commit"                     | Under `--no-commit` the invocation says so and `/tdd` returns file lists. The flag is the user's word.                    |
| "Every finding goes on the list, so every entry goes in the report"  | The list is your working set. The report carries confirmed defects and deviations; the rest stays on the list.            |
| "I fixed it, so it's worth reporting as a finding"                   | Work is a deviation when the plan did not say it, and nothing otherwise. A finding is a defect that is still there.       |
| "Listing everything lets the user decide what matters"               | Ranking is the job. The user approved a plan so they would not have to sift.                                              |
| "The plan prescribed it, so I note that I followed it"               | Followed with no cost → nothing. Followed with a cost → a finding, whoever prescribed it.                                 |
| "The user says it's too long — drop the weakest one"                 | Length pushback removes nothing confirmed. Re-rank and restate; the count stays.                                          |
| "It's a finding, so it waits for the findings-fix phase"             | Lines this execution wrote are the deliverable, not the repo. A gap there is the task unfinished. Fix it now, test first. |
| "Fixing it would be a Findings entry fixed too early"                | Only code the plan did not write is a finding. Approval requested the plan's own code correct.                            |
| "I'll fix this finding now while I'm in the file"                    | Findings are fixed once, in one batch, after the Final Task review. Mid-loop fixes hide in a task's commit.               |
| "The branch is ceremony for a one-task plan"                         | The branch is what keeps the base one commit per plan. The gate is not optional.                                          |
| "The tree is only dirty with unrelated files — carry on"             | Unrelated dirt is exactly what ends up in the wrong commit. Halt 4; the user decides.                                     |
| "A dirty tree ends the gate however the files relate to the plan"    | On your own plan branch the unfinished task's files are this run's earlier work. Resume; halt 4 names only other paths.   |
| "CI takes minutes — push and let the user watch it"                  | The ship phase watches. A red run fixed after the report is a second commit on the base.                                  |
| "The squash is trivial, I'll merge it myself"                        | Never on the base. The user invokes `/release merge`; the report says so.                                                 |
| "The target sha is right there in the plan"                          | The plan names a subject. The sha is looked up when the task is about to commit, after any fold that happened since.      |
| "The verdict is Verified; the note is only Reasoning"                | A gap the reviewer names is a refutation with the wrong label. Fix, re-dispatch that claim.                               |
| "I fixed the main gap; the others are minor"                         | Every gap the reviewer named stays open until its own claim is Verified. Fix all of them before re-dispatching.           |
| "Writing a test the plan never named is unrequested work"            | Every plan behavior comes with its test. One with no test is the cycle unfinished, not new scope.                         |
| "`/tdd` tasks: take its verdicts, never re-dispatch"                 | Its Verified verdicts. A claim it refuted and you fixed is open until the reviewer closes it.                             |
| "Mark it `unverified`; the Final Task re-checks it"                  | `unverified` is for findings you could not read. A claim you fixed is re-verified now, in its task.                       |
| "The Behavior's listed cases are examples; this one fits its intent" | The user approved the cases the Behavior names. A re-verify note about a case it does not name is a finding.              |
| "The user only asked which findings remain"                          | "we need to fix" is a fix request for the `needs decision` entries. Ledger first, one durable fix each, then `/tdd`.      |
| "I hit this bug while testing, so fixing it serves the plan"         | Its file is not in the plan's diff. Report it in one line; the workaround you used is a deviation.                        |
| "In-scope and broken, but I'll let the user pick the fix"            | No dependent at `file:line` → fix it in the batch. Asking hands back work the approval already granted.                   |
| "Out of scope, so I'll ask whether to fix it"                        | Out of scope is reported, never asked about. One line in Findings; the user starts the work if they want it.              |
| "Answering from memory is faster than reading the ledger"            | Memory gave 3, then 6, then 7. One Read of the ledger is the answer.                                                      |
| "The repo has no CI, so `--no-push` is implied"                      | Only the user passes `--no-push`. Push, poll twice, record `no branch CI` — observed, not assumed.                        |
| "I remember the ship phase well enough to run it"                    | A paraphrase drops the marker, the two-poll rule, the `--force` rule. Read `branch-flow.md` first.                        |
| "The watch exited 0, so CI is green"                                 | That is `tee`'s exit, or a wake-up. Green is `gh run view` showing `conclusion: success` on the pushed tip, nothing else. |

## Red Flags — Stop and Re-read Approval Is the Grant

- A message mid-plan that ends with a question mark that `tdd` did not prescribe
- A turn ending before the Final Task that is neither a pause nor a named halt
- `Skill(autocommit)` loaded a second time
- Either marker still present after the final report or a halt report, or `fix-ci-active` still
  present after the ship phase
- A Findings entry fixed before the findings-fix phase, or a `needs decision` entry fixed before the
  user approves that fix
- A findings-fix commit touching a file absent from the plan's diff before the findings-fix phase
- A question about an out-of-scope finding, or about an in-scope one with no dependent at
  `file:line`
- A commit or merge on the base branch, a `release.sh` invocation or `release-active` marker raised
  by this loop, or a push by this loop of anything but `plan/<slug>` (the dispatched `fix-ci` agent
  pushes its own `fix-ci/*` branch under its own rules)
- A task with a fold target committed with a composed message, or a `none` task committed as a fixup
- A report with no Ship section, or a Ship section that names a push instead of the merge command
- A Ship line saying `CI green` without `gh run view … conclusion: success` for the pushed tip in
  context, or one written from a watch's exit code
- A ship phase skipped without `--no-push` on the invocation, or a merge line whose `--force` does
  not match the CI result (`CI green` → none; anything else → `--force`)
- A Ship section with raw git commands (`git switch`, `git merge --squash`) instead of `Merge:
  /release merge [--force]`, or one silent about a finding that folds into a release commit
- A report entry with no `what it costs`, or one that begins with "I" (I fixed, I deleted, I left)
- A per-task file list, or a task described by what it built
- A confirmed finding gone from a reply after a "too long" complaint
- A gap in lines this execution wrote listed under Findings instead of fixed in its task — unless it
  is a re-verify note outside the task's Behaviors list (step 2)
- A refuted claim, or a reviewer note on a Verified claim, moved to `unverified`, Deviations, or the
  Final Task instead of fixed and re-dispatched
- A fix with no re-verify after it
- A re-dispatch after fixing only some of the gaps the reviewer named — every named gap is addressed
  before re-dispatching
- A finding count, or a done/not-done status, stated from memory instead of the ledger
