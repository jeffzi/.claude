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

**When the leaf declares an impact enum:** order the fix queue by its tier chain; within a tier,
keep the agent's order. A finding with no Impact line takes the top tier — never demoted for missing
metadata.

**Step 4 — Apply the fixes.** Load the leaf's step-4 skills before editing. Fix one finding at a
time. Done when the fix queue is empty — every `confirmed` finding applied, each naming the rule it
satisfies. A fix that cannot be applied moves to the report-only queue with its reason attached —
never dropped.

**Step 5 — Verify** with the leaf's checks.

**Step 6 — Report** with the leaf's template, under the report rules below.

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
