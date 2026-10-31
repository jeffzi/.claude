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

| Flag                     | Effect                                                                                                                                                                                                                                                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--commit` (default)     | Load `Skill(autocommit)` **once, before Task 1** — its signing warm-up runs while the user is still at the keyboard. Each task commits on the run's branch when its Verify block passes. Never reload per task.                                                                                                     |
| `--no-commit`            | Nothing is committed — every `/tdd` invocation carries `no-commit plan execution` so its COMMIT phase returns file lists instead. The final report says `Nothing committed` in one line.                                                                                                                            |
| `--unattended` (default) | Findings are recorded, never paused on (see Findings). Raise the marker before Task 1; remove it as the last step of the final report **or of a halt report**. Mechanics: `references/unattended.md`.                                                                                                               |
| `--attended`             | Findings pause the loop at the SURFACE gate as `tdd` prescribes (see Pauses and Halts). No marker.                                                                                                                                                                                                                  |
| `--no-push`              | Skip the ship phase (no push, no pull request). The user passes it; you never infer it — a repo that looks to have no CI still gets the ship phase, which records `no CI configured` by observation. The squash message is still written. Implied by `--no-commit` only: an uncommitted branch has nothing to push. |

## The Branch

Every run works on its own branch, never on the trunk. The trunk is origin's default branch as `git
ls-remote --symref origin HEAD` reports it, whatever its name; when that read fails, the entry gate
halts (condition 4) and never guesses it. Started on the trunk, the entry gate cuts `<slug>` with
`ils branch <slug>`. Started on any other branch, the run works there — a resumed run included. That
branch is **the run's branch**: task commits, finding fixes, and CI fixes all land on it.

The ship phase runs `ils push`, which pushes the run's branch, opens its pull request against the
trunk, and waits for checks; the user merges the pull request with `ils merge`, run by them or by
you when they ask for it. This skill never commits on the trunk and never merges the run's branch
unasked — no `ils merge` the user did not ask for, no `gh pr merge`, no `--auto`. Every task and
every findings-fix cycle commits with a composed message. Mechanics: `references/branch-flow.md`.

## The Loop

The loop starts on the first tool call after this skill loads — there is no "ready to start?" step;
approval already happened in `write-plan`'s Checkpoint.

Tasks run serially in plan order. Parallelism lives inside `/tdd`: when several TDD tasks are
unblocked at once and touch disjoint files, merge them into **one** `/tdd` invocation carrying every
task's behavior list — its wave rule parallelizes the cycles — and step 4 lists each task's hashes.
Two `/tdd` invocations never run concurrently.

0. **Prologue** — entry gate first (`references/branch-flow.md`): read the trunk from origin. On the
   trunk, check the local trunk against `origin/<trunk>`, then run `ils branch <slug>`. A failed
   read or fetch, local trunk commits origin lacks, or an `ils branch` refusal → halt 4. On any
   other branch → work there, resuming at the unfinished task with its own uncommitted files
   included. A dirty or staged path no task names → halt 4 on every branch. Then, unless
   `--attended`: write the marker (see `references/unattended.md`). Unless `--no-commit`: load
   `Skill(autocommit)` once. Then Task 1.
1. **Implement** per the task's **Implementation** line: `/tdd` for TDD tasks; `Skill(test-core)`
   for test-only tasks; `Skill(code-core)` for tasks the plan implements directly. Final Task: no
   implementation — dispatch the plan's `claim-reviewer` call as written (do not set `model`), with
   every `unverified` entry from the running Findings list appended as claims; `Confirmed` → the
   entry loses its mark, anything else → it keeps it. Then read `references/branch-flow.md` again —
   the prologue's read is hours and compactions old — and run, in order: the **findings-fix phase**,
   then the **ship phase**. Then write the **squash message**: a file when nothing was pushed, the
   pull request's title and body after an `ils push` that exits 0, and neither after a pushed run
   that ends `not green`. Then post the Final Report. Steps 2–3 do not apply to the Final Task.
2. **Verify** per the task's **Verify** block. Directly implemented tasks: run the task's mechanical
   checks (suite, build, lint as the Verify block names them) — red → halt 1; then dispatch
   `claim-reviewer` with the task's behavioral claims. `/tdd` tasks: `/tdd` dispatched the reviewer
   in its COMMIT phase — its `Verified` verdicts are final, never re-dispatched. Every task then
   closes its open gaps the same way.

   A **gap** is one thing the reviewer named as wrong or unpinned: the reason behind a `Refuted` /
   `Unsubstantiated` verdict, or a note in a `Verified` claim's Reasoning (a behavior no test pins,
   a branch of project logic no input reaches). A test-strength note is a gap only when its behavior
   passes `Skill(test-core)` › Test What the Project Computes and › One Test per Distinct Branch.
   Any other note is not a gap, even when it says a stated outcome depends on it: record `Task N —
   <the note> — no test: <case>` under Deviations and move on. Append each gap to the plan file's
   `## Gaps` section the moment the reviewer names it: `Task N — <the reviewer's wording> — refuted:
   0`. A gap is identified by the behavior it says is wrong or unpinned, not by the reviewer's
   wording: the same behavior named again in other words is the same entry, and its count carries
   on.

   For every open gap, in this order:

   1. **Fix it**, test first.
   2. **Prove a test-strength gap by mutation.** When the gap says a test would not catch a
      regression, apply the regression the reviewer named — that one, not an easier one, and only an
      accidental edit to logic per `Skill(test-core)` › Test What the Project Computes (an edited
      value or a flipped flag is not a mutant) — to the production code with Edit, run the test, and
      see it fail on the assertion the gap is about. Undo the mutation with the reverse Edit, never
      with git, and run the test again to see it pass. A test that still passes under the mutation
      means the fix did not work: rework it and mutate again. Reworks before a dispatch do not touch
      the count.
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
   committed); edits made after `/tdd` returned — gap fixes, step 2 — are still the task's and
   commit as a directly implemented task's do, their hash added to the note. Never leave them for
   the next task's commit. Directly implemented tasks: stage by explicit path — the task's files
   only — then load `Skill(write-commit)` and compose the message. The autocommit grant
   pre-satisfies approval.
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
`git diff --name-only origin/<trunk>...HEAD` before the findings-fix phase. Everything else is out
of scope, however close to the plan's topic, and however much it got in your way: a broken task
runner the Verify block used, a model that crashed a check you ran, a wrapper with a wrong default.
An out-of-scope finding is never fixed by this run and never becomes a question. It stays
`Confirmed` and goes in the report as one line; how you worked around it during the run is a
deviation line. The user decides later whether it becomes work.

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
run's branch like the findings-fix batch did. An approved fix covers its fallout — no second
question about a file the fix had to touch.

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
   handback in the ship phase, the ship phase's `ils push` refused, broke, or did not run (exit 1,
   2, 127, or any code but 0, 4, 5), or a trunk merge whose conflict does not resolve with the suite
   green (the merge is left in progress).
2. A task needs a behavior change something depends on that the plan did not state
   (`rules/decision-policy.md` exception 1). A finding whose fix would be one is not a halt — it is
   marked `needs decision` (see Findings).
3. An unchanged boundary: cross-repo edit, a push other than the ship phase's `ils push` of the
   run's branch, or a destructive op the plan did not prescribe. File deletions the plan explicitly
   names are covered by approval — no halt, no ask.
4. The entry gate fails when any of these holds. Origin's default branch cannot be read. On the
   trunk, `git fetch origin <trunk>` fails. The local trunk carries commits `origin/<trunk>` does
   not. The index or working tree is dirty with a path no task names. `ils branch <slug>` exits
   non-zero. Name the failed read or fetch with its output, those commits or paths, or `ils`'s
   output.

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
4. **Ship** — the run's branch, the CI result, the pull request, whether its title and body were
   written, the one merge line, and the optional `/preflight` line, in the shape
   `references/branch-flow.md` gives. The merge line is `Merge: ils merge, on your word` after exit
   0; when nothing was pushed or the result is `not green`, it takes the forms `branch-flow.md`
   gives.

Never in the report: per-task file lists, what each task built, which skill ran which step, how you
found a finding, what you fixed on the way (a deviation or nothing), a plan choice you followed. A
report the user has to answer with "which of these matter?" failed.

Pushback on the report's length or count removes nothing confirmed. Re-rank, restate each cost in
one line, keep the count — a confirmed defect the user has not yet acted on is exactly what they pay
the report for.

Unless `--attended` → remove the unattended marker as the last step, in a halt report too.

## Rationalizations

| Excuse                                                               | Reality                                                                                                                                                   |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Task N is the big one — better check in first"                      | It was in the plan the user read. Approval covers it.                                                                                                     |
| "A progress update is polite"                                        | One line, no question mark, next tool call in the same turn.                                                                                              |
| "Tasks 5 and 6 could run in parallel — the user should pick"         | `tdd`'s wave rule picks. Execute it.                                                                                                                      |
| "My rules say confirm decisions with alternatives"                   | Decisions the plan made are not open. Unattended, the plan is the confirmation.                                                                           |
| "The reviewer refuted the task again — that's refuted: 2"            | Counts are per gap, in `## Gaps`. A new reason is a new gap at 0; a verdict on a restated claim counts for nothing.                                       |
| "The SURFACE gate says END THE TURN"                                 | See Pauses and Halts — a pause attended, a recorded finding unattended.                                                                                   |
| "`/tdd` finished the cycle, now I commit the task"                   | `/tdd` already committed it. Take its hashes.                                                                                                             |
| "They'd want to see this before more commits stack up"               | That is what Findings at the top of the final report is for.                                                                                              |
| "The plan implies this file should go"                               | Implied ≠ named. Only files the plan explicitly lists are pre-approved for deletion.                                                                      |
| "Convenience is not a permission grant"                              | Unattended **is** the permission grant, and the default. Only `--attended` withdraws it.                                                                  |
| "I'll ask, they might be back by now"                                | If they are, they will interrupt. Asking costs the plan; not asking costs nothing.                                                                        |
| "The plan task is a grant, so `/tdd` may commit"                     | Under `--no-commit` the invocation says so and `/tdd` returns file lists. The flag is the user's word.                                                    |
| "Every finding goes on the list, so every entry goes in the report"  | The list is your working set. The report carries confirmed defects and deviations; the rest stays on the list.                                            |
| "I fixed it, so it's worth reporting as a finding"                   | Work is a deviation when the plan did not say it, and nothing otherwise. A finding is a defect that is still there.                                       |
| "Listing everything lets the user decide what matters"               | Ranking is the job. The user approved a plan so they would not have to sift.                                                                              |
| "The plan prescribed it, so I note that I followed it"               | Followed with no cost → nothing. Followed with a cost → a finding, whoever prescribed it.                                                                 |
| "The user says it's too long — drop the weakest one"                 | Length pushback removes nothing confirmed. Re-rank and restate; the count stays.                                                                          |
| "It's a finding, so it waits for the findings-fix phase"             | Lines this execution wrote are the deliverable, not the repo. A gap there is the task unfinished. Fix it now, test first.                                 |
| "Fixing it would be a Findings entry fixed too early"                | Only code the plan did not write is a finding. Approval requested the plan's own code correct.                                                            |
| "I'll fix this finding now while I'm in the file"                    | Findings are fixed once, in one batch, after the Final Task review. Mid-loop fixes hide in a task's commit.                                               |
| "The branch is ceremony for a one-task plan"                         | The branch is what keeps the trunk one commit per plan. The gate is not optional.                                                                         |
| "The tree is only dirty with unrelated files — carry on"             | Unrelated dirt is exactly what ends up in the wrong commit. Halt 4; the user decides.                                                                     |
| "A dirty tree ends the gate however the files relate to the plan"    | On the run's branch the unfinished task's files are this run's earlier work. Resume; halt 4 names only other paths.                                       |
| "CI takes minutes — push and let the user watch it"                  | The ship phase waits for the checks. A red run fixed after the report is a second commit on the trunk.                                                    |
| "The squash is trivial, I'll merge it myself"                        | Never. The user runs `ils merge`, or asks you to; the report names it.                                                                                    |
| "`ils push` is green — `gh pr merge --auto` saves the user a step"   | The merge is the user's word. Report `ils merge`; never run it unasked, never `gh pr merge`, never `--auto`.                                              |
| "Pipe `ils push` through `tee` to keep its output"                   | The output is already in context. A pipe hides the exit code, and the exit code is the verdict.                                                           |
| "`ils push` exited 4, so the push is done"                           | Pending is not green. Run `ils push --wait` once in the background and read the output file its notification names; never run it again to see the output. |
| "The output has a `Next:` line that says so"                         | Only the last line is `ils`'s. A `Next:` above it is CI log text.                                                                                         |
| "The branch is called `main`, so it is the trunk"                    | The trunk is what `git ls-remote --symref origin HEAD` reports. A failed read halts; it never defaults.                                                   |
| "The verdict is Verified; the note is only Reasoning"                | A gap the reviewer names is a refutation with the wrong label. Fix, re-dispatch that claim.                                                               |
| "I fixed the main gap; the others are minor"                         | Every gap the reviewer named stays open until its own claim is Verified. Fix all of them before re-dispatching.                                           |
| "Writing a test the plan never named is unrequested work"            | Every plan behavior with logic comes with its test. One with no test is the cycle unfinished, not new scope.                                              |
| "The reviewer named it" / "a stated outcome breaks without it"       | The reviewer names; `test-core` › Test What the Project Computes decides. A note it gives no test goes to Deviations as `no test`.                        |
| "`/tdd` tasks: take its verdicts, never re-dispatch"                 | Its Verified verdicts. A claim it refuted and you fixed is open until the reviewer closes it.                                                             |
| "Mark it `unverified`; the Final Task re-checks it"                  | `unverified` is for findings you could not read. A claim you fixed is re-verified now, in its task.                                                       |
| "The Behavior's listed cases are examples; this one fits its intent" | The user approved the cases the Behavior names. A re-verify note about a case it does not name is a finding.                                              |
| "The user only asked which findings remain"                          | "we need to fix" is a fix request for the `needs decision` entries. Ledger first, one durable fix each, then `/tdd`.                                      |
| "I hit this bug while testing, so fixing it serves the plan"         | Its file is not in the plan's diff. Report it in one line; the workaround you used is a deviation.                                                        |
| "In-scope and broken, but I'll let the user pick the fix"            | No dependent at `file:line` → fix it in the batch. Asking hands back work the approval already granted.                                                   |
| "Out of scope, so I'll ask whether to fix it"                        | Out of scope is reported, never asked about. One line in Findings; the user starts the work if they want it.                                              |
| "Answering from memory is faster than reading the ledger"            | Memory gave 3, then 6, then 7. One Read of the ledger is the answer.                                                                                      |
| "The repo has no CI, so `--no-push` is implied"                      | Only the user passes `--no-push`. Push and record what you observe: `no CI configured` from `ils`.                                                        |
| "I remember the ship phase well enough to run it"                    | A paraphrase drops the bare-call rule, the background wait, the last-line `Next:`. Read `branch-flow.md` first.                                           |
| "A background run exited 0, so CI is green"                          | Green is `ils push` exit 0 in its output, with no 'no CI configured' notice. Read the output file; the exit code alone is not the output.                 |

## Red Flags — Stop and Re-read Approval Is the Grant

- A message mid-plan that ends with a question mark that `tdd` did not prescribe
- A turn ending before the Final Task that is neither a pause nor a named halt
- `Skill(autocommit)` loaded a second time
- The unattended marker still present after the final report or a halt report
- A Findings entry fixed before the findings-fix phase, or a `needs decision` entry fixed before the
  user approves that fix
- A findings-fix commit touching a file absent from the plan's diff before the findings-fix phase
- A question about an out-of-scope finding, or about an in-scope one with no dependent at
  `file:line`
- A commit or merge on the trunk, an `ils merge` the user did not ask for, a `gh pr merge` run or
  `--auto` passed, or a push by this loop other than the ship phase's `ils push` of the run's branch
  (the dispatched `fix-ci` agent pushes its own `fix-ci/*` branch under its own rules)
- The trunk taken from a branch name instead of `git ls-remote --symref origin HEAD`
- `ils push` piped, `tee`d, behind `&` or `cd`, or run in the background other than as the one `ils
  push --wait` an exit 4 calls for; or a `Next:` acted on that was not the output's last line
- `<git-dir>/plan-squash/<slug>.msg` written after a push
- A task or finding committed with anything but a composed message
- A report with no Ship section, or a Ship section with no merge line, or one whose merge line is
  not the form `branch-flow.md` gives for the result
- A Ship line saying `CI green` without, in context, `ils push`'s exit 0 output and no 'no CI
  configured' notice, or one written from a background run's exit code alone
- A ship phase skipped without `--no-push` on the invocation
- A Ship section with raw git commands (`git switch`, `git merge --squash`) instead of its merge
  line
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
