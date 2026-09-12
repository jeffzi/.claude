---
name: execute-plan
description: >
  Use when an approved plan in `.planning/` is ready to run — "execute the plan",
  "go ahead with the plan", or invoked via /execute-plan. Also use mid-plan when tempted to ask
  "should I continue?", "want me to launch the next task?", or to end the turn on a progress
  update. Not for writing the plan — use write-plan. Not for an ad hoc single task — use tdd or
  fix.
argument-hint: "[plan-slug] [--commit|--no-commit] [--attended|--unattended]"
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

| Flag                     | Effect                                                                                                                                                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--commit`               | Load `Skill(autocommit)` **once, before Task 1** — its signing warm-up runs while the user is still at the keyboard. Each task commits when its Verify block passes. Never reload per task.           |
| `--no-commit` (default)  | Nothing is committed — every `/tdd` invocation carries `no-commit plan execution` so its COMMIT phase returns file lists instead. The final report says `Nothing committed` in one line.              |
| `--unattended` (default) | Findings are recorded, never paused on (see Findings). Raise the marker before Task 1; remove it as the last step of the final report **or of a halt report**. Mechanics: `references/unattended.md`. |
| `--attended`             | Findings pause the loop at the SURFACE gate as `tdd` prescribes (see Pauses and Halts). No marker.                                                                                                    |

## The Loop

The loop starts on the first tool call after this skill loads — there is no "ready to start?" step;
approval already happened in `write-plan`'s Checkpoint.

Tasks run serially in plan order. Parallelism lives inside `/tdd`: when several TDD tasks are
unblocked at once and touch disjoint files, merge them into **one** `/tdd` invocation carrying every
task's behavior list — its wave rule parallelizes the cycles — and step 4 lists each task's hashes.
Two `/tdd` invocations never run concurrently.

0. **Prologue** — unless `--attended`: write the marker (see `references/unattended.md`).
   `--commit`: load `Skill(autocommit)` once. Then Task 1.
1. **Implement** per the task's **Implementation** line: `/tdd` for TDD tasks; `Skill(test-core)`
   for test-only tasks; `Skill(code-core)` for tasks the plan implements directly. Final Task: no
   implementation — dispatch the plan's `claim-reviewer` call as written (do not set `model`), with
   every `unverified` entry from the running Findings list appended as claims; `Confirmed` → the
   entry loses its mark, anything else → it keeps it. Then the Final Report. Steps 2–3 do not apply
   to the Final Task.
2. **Verify** per the task's **Verify** block. `/tdd` tasks: `/tdd` ran the block in its COMMIT
   phase — take its verdicts, never re-dispatch. Directly implemented tasks: run the task's
   mechanical checks (suite, build, lint as the Verify block names them) — red → halt 1; then
   dispatch `claim-reviewer` with the task's behavioral claims; `Refuted` / `Unsubstantiated` → fix,
   re-verify that claim once; still failing → halt 1.
3. **Commit** — `--commit` only. `/tdd` tasks: take the hashes `/tdd` returned (already committed).
   Directly implemented tasks: load `Skill(write-commit)`, stage by explicit path — the task's files
   only; the autocommit grant pre-satisfies approval.
4. **Progress note** — one line, then the next tool call: `Task N done — <hashes>` or
   `Task N done —
   uncommitted: <files>`.

Done when the Final Task's `claim-reviewer` has run and the final report is posted.

## Findings

A finding is a defect in the repo: `file:line — what's wrong — what it costs`. In or out of the
plan's scope, caused by the plan or not — a defect the plan prescribed is still a finding; a plan
choice with no cost is not one. Confirmed means you read the code at that line and the defect is
there, or `claim-reviewer` returned `Confirmed`; anything short of that goes on the list marked
`unverified` and is confirmed at the Final Task. Never fix a finding unrequested; never drop one — a
finding the user dismisses stays on the list, marked dismissed.

Never a finding: work you did (a lint fix, a test you deleted, a file you touched — that is a
deviation or nothing); a cleanup, duplication, style, or "worth doing if you're in the file" — taste
has no `what it costs`; a check that passed.

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

**Halts** — the only three, in either mode:

1. Verification still red after step 2's single re-verify — a `tdd-cycle` `STUCK` or `TEST_FLAWED`
   status is this condition.
2. A task needs a behavior change something depends on that the plan did not state
   (`rules/decision-policy.md` exception 1).
3. An unchanged boundary: cross-repo edit, push, or a destructive op the plan did not prescribe.
   File deletions the plan explicitly names are covered by approval — no halt, no ask.

A halt is a report — tasks done, the blocked task and why, findings so far, marker removed — then
the turn ends. It names the condition from this list. It is never a question.

## Final Report

The report is what the user acts on, not an account of what you did. Three parts, in this order,
nothing else:

1. **Findings** — every confirmed entry, `file:line — what's wrong — what it costs`, the one that
   most changes what the user does next first. An entry still `unverified`, refuted, or dismissed
   stays on the running list and off the report.
2. **Deviations** — every entry, `Task N — plan said — did — why`. None → no heading.
3. **State** — `--commit` → the hashes, one line; `--no-commit` → `Nothing committed`. Each
   verification command as `command → result`, one line. The `/preflight` reminder the plan's Final
   Task prescribes.

Never in the report: per-task file lists, what each task built, which skill ran which step, how you
found a finding, what you fixed on the way (a deviation or nothing), a plan choice you followed. A
report the user has to answer with "which of these matter?" failed.

Pushback on the report's length or count removes nothing confirmed. Re-rank, restate each cost in
one line, keep the count — a confirmed defect the user has not yet acted on is exactly what they pay
the report for.

Unless `--attended` → remove the marker as the last step.

## Rationalizations

| Excuse                                                              | Reality                                                                                                             |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| "Task N is the big one — better check in first"                     | It was in the plan the user read. Approval covers it.                                                               |
| "A progress update is polite"                                       | One line, no question mark, next tool call in the same turn.                                                        |
| "Tasks 5 and 6 could run in parallel — the user should pick"        | `tdd`'s wave rule picks. Execute it.                                                                                |
| "The hook says confirm decisions with alternatives"                 | Decisions the plan made are not open. Unattended, the hook itself says the plan is the confirmation.                |
| "The SURFACE gate says END THE TURN"                                | See Pauses and Halts — a pause attended, a recorded finding unattended.                                             |
| "`/tdd` finished the cycle, now I commit the task"                  | `/tdd` already committed it. Take its hashes.                                                                       |
| "They'd want to see this before more commits stack up"              | That is what Findings at the top of the final report is for.                                                        |
| "The plan implies this file should go"                              | Implied ≠ named. Only files the plan explicitly lists are pre-approved for deletion.                                |
| "Convenience is not a permission grant"                             | Unattended **is** the permission grant, and the default. Only `--attended` withdraws it.                            |
| "I'll ask, they might be back by now"                               | If they are, they will interrupt. Asking costs the plan; not asking costs nothing.                                  |
| "The plan task is a grant, so `/tdd` may commit"                    | Under `--no-commit` the invocation says so and `/tdd` returns file lists. The flag is the user's word.              |
| "Every finding goes on the list, so every entry goes in the report" | The list is your working set. The report carries confirmed defects and deviations; the rest stays on the list.      |
| "I fixed it, so it's worth reporting as a finding"                  | Work is a deviation when the plan did not say it, and nothing otherwise. A finding is a defect that is still there. |
| "Listing everything lets the user decide what matters"              | Ranking is the job. The user approved a plan so they would not have to sift.                                        |
| "The plan prescribed it, so I note that I followed it"              | Followed with no cost → nothing. Followed with a cost → a finding, whoever prescribed it.                           |
| "The user says it's too long — drop the weakest one"                | Length pushback removes nothing confirmed. Re-rank and restate; the count stays.                                    |

## Red Flags — Stop and Re-read Approval Is the Grant

- A message mid-plan that ends with a question mark that `tdd` did not prescribe
- A turn ending before the Final Task that is neither a pause nor a named halt
- `Skill(autocommit)` loaded a second time
- Marker still present after the final report or a halt report
- A Findings entry fixed without a request
- A report entry with no `what it costs`, or one that begins with "I" (I fixed, I deleted, I left)
- A per-task file list, or a task described by what it built
- A confirmed finding gone from a reply after a "too long" complaint
