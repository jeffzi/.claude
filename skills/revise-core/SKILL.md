---
name: revise-core
description: >
  Use when a revise-* leaf loads the shared protocol before step 1. Never invoke directly.
user-invocable: false
---

# Revise Protocol — Shared Core

Every `/revise-*` leaf loads this skill before step 1 and declares the domain slots: the `vet-*`
reviewer, the target filter and no-argument file set, an impact enum (optional), any extra triage
branches (step 3), any extra reviewer dispatch beyond the bucketed calls (step 2), the step-4 skill
loads, the verify checks, and the report template.

## Protocol

The leaf's numbered steps refine these rules; the rules here bind every leaf. Never set `model` on
an **Agent** call — each agent defines its own. Violating the letter of this protocol is violating
its spirit — there are no technicalities.

**Step 0 — Check for a checkpoint.** Before any leaf step, Glob `.planning/revise-<leaf>-*.md`. This
step is never skipped — the leaf's numbered steps start after it. Found a checkpoint with
`status: in-progress` and `pending` findings?

- Same target → skip steps 1–3b and enter step 4 with its queue: the reviews are already paid for.
- Different target, or no argument given → ask the user: resume the checkpoint or start fresh on the
  new scope. Never silently ignore an in-progress checkpoint.

**Step 1 — Resolve targets and scope.** A path argument → those files, reduced by the leaf's target
filter, scope `full`. No argument → the leaf's no-argument file set, scope `changed`.

**Step 2 — Dispatch the reviewer.** Bucket the resolved files by parent directory — the target root
is its own bucket — and split any bucket over 10 files into roughly even chunks. One **Agent** call
per bucket, `subagent_type:` the leaf's `vet-*` agent, all in one parallel message. Pass each agent
its bucket's file list, the review scope, and the diff when scope is `changed`. Merge every bucket's
`### Finding N` blocks into one queue before step 3.

**Step 3 — Triage the findings** using the verdict the agent assigned:

- `false-positive` → discard.
- `confirmed` → fix queue.
- `suspected` → report-only queue.
- `unconfirmed` → adjudication (step 3a).

Leaf-declared routing branches gate findings out before anything enters the fix queue; apply them
first.

**Step 3a — Adjudicate unconfirmed findings.** When any remain after leaf-declared branches run,
dispatch one **Agent** call, `subagent_type: claim-reviewer`. Carry one claim per `unconfirmed`
finding, stating it as an implemented fact. Route the results:

- `Verified` with claim-reviewer score ≥ 75 → fix queue as `confirmed`, keeping its Impact tag.
- `Refuted` → discard, reported as an adjudicated false positive.
- Otherwise → report-only queue with reason "adjudicated: unsubstantiated".

**Step 3b — Checkpoint the queue.** Write `.planning/revise-<leaf>-<slug>.md` — `<leaf>` is the
invoked command (`test`, `code`, …), `<slug>` kebab-cased from the path argument or `changed` for
the no-argument scope. Header: leaf, target, scope, `status: in-progress`. Body: every finding's
full `### Finding N` block with a `Status:` line — `pending` for the fix queue,
`report-only: <reason>`, or `discarded`. Step 4 never starts before this file exists: writing it
requires every bucket merged and triage complete, so a reviewer still running means no fixing yet.

**When the leaf declares an impact enum:** order the fix queue by its tier chain; within a tier,
keep the agent's order. A finding with no Impact line takes the top tier — never demoted for missing
metadata.

**Step 4 — Apply the fixes.** Load the leaf's step-4 skills before editing. The checkpoint file is
the queue — read `pending` findings from it, never from conversation memory, and update each
finding's `Status:` (`fixed`, or `report-only: <reason>`) as it lands, so an interrupted run resumes
from the file. Fix one finding at a time. Done when the fix queue is empty — every `confirmed`
finding applied, each naming the rule it satisfies. Exactly two things move a queued finding to the
report-only queue, reason attached, never dropped: a leaf-declared surfacing rule routes it out, or
its applied fix fails the leaf's verify checks and is reverted. Effort is not a third: file count,
breadth, "requires a shared fixture", or "deserves its own dedicated pass" never route a finding out
— a `confirmed` finding that is laborious is applied in this run, however many files it touches.

**Step 5 — Verify** with the leaf's checks.

**Step 6 — Report** with the leaf's template, under the report rules below — generated from the
checkpoint file, which now has no `pending` findings. Set its header to `status: complete`, then ask
the user whether to delete the checkpoint or keep it; never delete without asking.

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "what would you fix" —
stop after step 3 (including adjudication) and report the findings. Do not apply anything.

## Report rules

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop. Fixed rows
appear in fix order — impact tier first. Every report-only finding appears in the left-alone section
with its verdict and the reason it was not fixed — no finding leaves the pipeline unreported.

## Rationalizations

| Excuse                                                | Reality                                                                |
| ----------------------------------------------------- | ---------------------------------------------------------------------- |
| "One reviewer call is cheaper than five buckets"      | A saturated reviewer misses findings; the buckets are the review.      |
| "Opus reviews better than the agent's default"        | The agent declares its own model; overriding it downgrades the review. |
| "These unconfirmed findings are obviously nits"       | Every `unconfirmed` finding is adjudicated, no exceptions.             |
| "The leaf's triage branches don't apply here"         | They gate findings out before the verdict does; run them first.        |
| "The user said review-only but clearly wants the fix" | Review-only is a legitimate request; stop after step 3.                |
| "This finding is too broad — it needs its own pass"   | Breadth is effort, not a verdict. The fix queue drains this run.       |
| "Early buckets are back — I can start fixing those"   | Step 4 is gated on the checkpoint; no file, no fixes.                  |
| "The leaf's process starts at step 1"                 | Step 0 runs first, every invocation. Glob before anything else.        |
