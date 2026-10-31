---
name: revise-core
description: >
  Use when a revise-* leaf loads the shared protocol before step 1. Never invoke directly.
user-invocable: false
---

# Revise Protocol — Shared Core

Every `/revise-*` leaf loads this skill before step 1 and declares these slots:

| Slot                                                                             | Used by |
| -------------------------------------------------------------------------------- | ------- |
| Target filter, no-argument file set                                              | Step 1  |
| `vet-*` reviewers (one or more per bucket), suite agent (optional)               | Step 2  |
| Extra triage branches                                                            | Step 3  |
| Impact enum (optional), fix-order precedence, pre-fix baseline for verify checks | Step 3b |
| Step-4 skills; surfacing rules (route a finding report-only)                     | Step 4  |
| Verify checks                                                                    | Step 5  |
| Report template                                                                  | Step 6  |

## Protocol

These rules bind every leaf; the leaf's steps refine them. Never set `model` on an **Agent** call.
Violating the letter of this protocol is violating its spirit.

**Step 0 — Resume check.** Runs first, every invocation. In-progress checkpoints (blank = none):

```!
find .planning -maxdepth 1 -name 'revise-*.md' -exec grep -l '^status: in-progress' '{}' + 2>/dev/null | sort || true
```

Keep the `revise-<leaf>-*` entries — never Glob for more. Act on the first matching row:

| Case                                                | Action                                                                                                                                                          |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Review-only request                                 | Never resume — see Review-only requests                                                                                                                         |
| No entry for this leaf                              | Step 1                                                                                                                                                          |
| Path argument; its slug matches an entry            | Resume: `pending` findings → step 4; none → step 5. Verify against the header's baseline. Never re-review, never rewrite it. Name any other entry for this leaf |
| No argument; `revise-<leaf>-changed.md` is an entry | Ask: resume, or start fresh — the changed-file set may have moved since. Name any other entry for this leaf                                                     |
| Any other entry                                     | Ask: resume it, or start fresh on the new scope. Never silently ignore it. Start fresh → set its header to `status: abandoned` before step 1                    |

**Step 1 — Resolve targets.**

| Argument | Files                              | Scope     |
| -------- | ---------------------------------- | --------- |
| Path     | Its files, after the leaf's filter | `full`    |
| None     | The leaf's no-argument file set    | `changed` |

**Step 2 — Dispatch the reviewers.**

| Stage | Rule                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Group | One bucket per parent directory; the target root is its own bucket                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Fold  | A directory of 5 files or fewer joins its parent's bucket, deepest first, while it stays ≤ 10                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Split | A bucket over 10 files splits into even chunks                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Suite | Directory target, leaf declares a suite agent: once per distinct subtree — each directory holding a target file, plus the root when it holds none directly — scope `full`, never per bucket, whatever the file count. File target or `changed` scope: none                                                                                                                                                                                                                                                          |
| Merge | Renumber the merged queue sequentially; step 3b, the forks and the report use those numbers. Two findings on the same violation — same rule, same subject (symbol, fixture, constant, seam) — with overlapping files become one, whether they came from two suite scopes, two reviewers on one bucket, or a bucket and a suite scope: the union of their files, the higher verdict and Impact, the larger finding's Reasoning plus the other's locations. Different subjects never merge, whatever files they share |

One **Agent** call per bucket per declared reviewer, and one per suite scope, one parallel group
launched per `rules/skill-loading.md`; step 3 waits for every call, suite scopes included. Bucket
calls carry files, scope, and the diff when scope is `changed`. Merge every `### Finding N` block
into one queue.

**Step 3 — Triage.** The leaf's triage branches gate findings out first; the verdict routes the
rest:

| Verdict          | Route             |
| ---------------- | ----------------- |
| `false-positive` | discard           |
| `confirmed`      | fix queue         |
| `suspected`      | report-only queue |
| `unconfirmed`    | step 3a           |

**Step 3a — Adjudicate.** When `unconfirmed` findings remain, one **Agent** call, `subagent_type:
claim-reviewer`, one claim per finding stated as an implemented fact:

| Result                 | Route                                                |
| ---------------------- | ---------------------------------------------------- |
| `Verified`, score ≥ 75 | fix queue as `confirmed`, Impact kept                |
| `Refuted`, score ≥ 75  | `discarded: adjudicated false positive`              |
| Anything else          | report-only, reason `adjudicated: <verdict> <score>` |

**All clean** — every reviewer call, leaf extras included, returned `No findings.` or was itself
discarded (`STATUS: WRONG_INPUT`) → no checkpoint, a one-line report naming any discarded reviewer,
stop.

**Step 3b — Checkpoint the queue.** Write `.planning/revise-<leaf>-<slug>.md` — `<leaf>` the command
(`code`, `test`, …), `<slug>` kebab-cased from the path argument, or `changed`. Header (YAML front
matter): leaf, target, scope, `status: in-progress`, and the leaf's pre-fix baseline, if any. Body:
every `### Finding N` block with a `Status:` — `pending`, `report-only: <reason>`, `discarded` or
`discarded: adjudicated false positive` — the `pending` ones in fix order, sorted by:

| Key | Rule                                                        |
| --- | ----------------------------------------------------------- |
| 1   | The leaf's fix-order precedence (its "apply … first" rules) |
| 2   | The impact tier chain; no Impact line → top tier            |
| 3   | The agent's order                                           |

Everything downstream follows this order. No fix before this file, and it needs every bucket merged.

**Step 4 — Apply the fixes** from the checkpoint, never from memory. Findings sharing any file share
a **transitive file group**:

| Groups   | Apply                                                                                                                                                                                                                     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One      | Inline: load the leaf's step-4 skills, fix one finding at a time in checkpoint order, set each `Status:` (`fixed` or `report-only: <reason>`) as it lands                                                                 |
| Multiple | Read `references/fork-dispatch.md`, then one `subagent_type: "fork"` **Agent** call per group, launched in parallel per `rules/skill-loading.md`. A refused fork's findings stay `pending` for its relaunch, never inline |

Done when nothing is `pending`. Only a leaf surfacing rule, a fork `FAILED` or a step-5 revert sends
a queued finding to report-only, reason attached. Effort never does: a `confirmed` finding is
applied this run, however many files, fixtures or "dedicated passes" it needs.

**Step 5 — Verify** with the leaf's checks. A failing check → read `references/verify-failure.md`
before touching a file: it reverts only the culprit findings, with inverse edits — never `git
restore`, `git checkout` or `git stash`. Done when every check passes and every `fixed` finding
survived that run.

**Step 6 — Report** with the leaf's template, from the checkpoint. Set its header to `status:
complete`, then ask whether to delete or keep it; never delete unasked.

## Review-only requests

"Just review", "report only", "what would you fix": run steps 1–3a fresh, write no checkpoint, apply
nothing. Leave any existing checkpoint untouched and name it in the report.

## Report rules

Omit empty sections. Fixed rows follow checkpoint order. Every report-only finding appears under
left alone, with verdict and reason. List adjudicated false positives one line each under "Refuted
by adjudication"; never plain `false-positive` discards.

## Red flags

| Signal                                                                                      | Breaks               |
| ------------------------------------------------------------------------------------------- | -------------------- |
| Reaching step 1 without reading step 0's list, or Globbing checkpoints                      | Step 0               |
| Resuming a `changed` checkpoint without asking, or an entry left unnamed                    | Step 0               |
| Another target's checkpoint resumed or ignored without asking                               | Step 0               |
| A resumed checkpoint rewritten at step 3b                                                   | Step 0               |
| A checkpoint header without the leaf's baseline, or a resumed run re-measuring it           | Step 3b              |
| One reviewer call for several buckets; `model` set on any call                              | Step 2, Protocol     |
| A directory left without the leaf's suite reviewer, or the root without one                 | Step 2               |
| Buckets dispatched one at a time                                                            | Step 2               |
| A verdict routed before the leaf's triage branches ran                                      | Step 3               |
| An `unconfirmed` finding dropped or fixed without adjudication                              | Step 3a              |
| A checkpoint on a run where every call returned `No findings.`, or a stop on a mixed result | All clean            |
| Ordering decided anywhere but step 3b                                                       | Step 3b              |
| Editing with no checkpoint, or while a reviewer still runs                                  | Step 3b              |
| Disjoint groups fixed inline one after another                                              | Step 4               |
| A refused fork's findings applied inline                                                    | Step 4               |
| Forks dispatched before reading `references/fork-dispatch.md`, or one at a time             | Step 4               |
| "Dedicated pass" next to a `confirmed` finding                                              | Step 4               |
| `git restore`, `git checkout` or `git stash` in step 5                                      | Step 5               |
| A `Refuted` below 75 discarded instead of sent report-only                                  | Step 3a              |
| A fork applying a finding a surfacing rule routes away, or no `SURFACED` return             | Step 4               |
| An adjudicated false positive missing from the report                                       | Report rules         |
| A file touched after a failed check before reading `references/verify-failure.md`           | Step 5               |
| A checkpoint written, or a fix applied, on a review-only run                                | Review-only requests |
| The checkpoint's queue reported in place of a fresh review                                  | Review-only requests |

## Rationalizations

| Excuse                                                | Reality                                                                   |
| ----------------------------------------------------- | ------------------------------------------------------------------------- |
| "One reviewer call is cheaper than five buckets"      | A saturated reviewer misses findings; the buckets are the review.         |
| "A one-file directory has nothing to cross-check"     | The protocol sets the count; the suite agent scales by inventory.         |
| "Opus reviews better than the agent's default"        | The agent declares its own model; overriding it downgrades the review.    |
| "These unconfirmed findings are obviously nits"       | Every `unconfirmed` finding is adjudicated, no exceptions.                |
| "The leaf's triage branches don't apply here"         | They gate findings out before the verdict does; run them first.           |
| "The user said review-only but clearly wants the fix" | Review-only is a legitimate request; nothing is applied.                  |
| "Review-only, so I'll report the checkpoint's queue"  | Review-only reviews fresh; the checkpoint stays untouched, named.         |
| "This finding is too broad — it needs its own pass"   | Breadth is effort, not a verdict. The fix queue drains this run.          |
| "Early buckets are back — I can start fixing those"   | Step 4 is gated on the checkpoint; no file, no fixes.                     |
| "48 findings — I'll just work through them in order"  | Sequential fixing wastes disjoint groups. Multiple groups → forks.        |
| "The leaf's process starts at step 1"                 | Step 0 runs first, every invocation, from the injected list.              |
| "A Glob is cheap — I'll double-check the list"        | The list is the check. A Glob is the step done twice, differently.        |
| "Suite-first is a step-4 rule, not checkpoint order"  | Leaf precedence is fix order; step 3b writes it into the checkpoint.      |
| "Parallel agents slowed things down — one at a time"  | Parallel is the protocol; `rules/skill-loading.md` already caps the load. |
| "The limit refused the fork, so I'll fix it inline"   | The fork never started. Relaunch it after your next completion.           |
| "`git restore` is one command; the file is all mine"  | Inverse edits only. A git revert can take the user's work with it.        |
