---
name: revise-core
description: >
  Use when a revise-* leaf loads the shared protocol before step 1. Never invoke directly.
user-invocable: false
---

# Revise Protocol — Shared Core

Every `/revise-*` leaf loads this skill before step 1 and declares the domain slots: the `vet-*`
reviewer, the target filter and no-argument file set, an impact enum (optional), the step-4 skill
loads, the verify checks, and the report template.

## Protocol

The leaf's numbered steps refine these rules; the rules here bind every leaf.

**Step 1 — Resolve targets and scope.** A path argument → those files, scope `full`. No argument →
the leaf's no-argument file set, scope `changed`.

**Step 2 — Dispatch the reviewer.** One **Agent** call, `subagent_type:` the leaf's `vet-*` agent.
**Do NOT set model — the agent defines its own.** Pass the file list, the review scope, and the diff
when scope is `changed`. The agent returns `### Finding N` blocks.

**Step 3 — Triage the findings** using the verdict the agent assigned:

- `false-positive` → discard.
- `confirmed` → fix queue.
- `suspected` → report-only queue.
- `unconfirmed` → adjudication (step 3a).

A leaf may declare additional routing branches that gate findings out before anything enters the fix
queue; apply those branches first.

**Step 3a — Adjudicate unconfirmed findings.** When `unconfirmed` findings exist after leaf-declared
branches run, dispatch one **Agent** call, `subagent_type: claim-reviewer` (do NOT set model — the
agent defines its own). Carry one claim per `unconfirmed` finding, stating it as an implemented
fact. Route the results:

- `Verified` with claim-reviewer score ≥ 75 → promote to the fix queue as `confirmed`, keeping its
  original Impact tag.
- `Refuted` → discard, reported as an adjudicated false positive.
- Otherwise → report-only queue with reason "adjudicated: unsubstantiated".

**When the leaf declares an impact enum:** order the fix queue by impact, not by finding number,
following the leaf's tier chain. Within one impact tier, keep the agent's order. A finding with no
Impact line is treated as the leaf's top tier — never demoted for missing metadata. In the report,
Fixed rows appear in fix order — impact tier first.

**Step 4 — Apply the fixes.** Load the leaf's step-4 skills before editing. Fix one finding at a
time.

**Step 5 — Verify** with the leaf's checks.

**Step 6 — Report** with the leaf's template.

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "don't change anything",
"what would you fix" — stop after step 3 (including adjudication) and report the findings. Do not
apply anything. This is a legitimate request, not an obstacle to work around.

## Report rules

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Skipping the leaf's declared triage branches → they gate findings out before the verdict does
- ❌ Skipping adjudication because the unconfirmed queue "looks like style nits" → every
  `unconfirmed` finding is adjudicated, no exceptions
