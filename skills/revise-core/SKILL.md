---
name: revise-core
description: >
  Shared protocol for the revise-* skills — process skeleton, score-gate triage, enum-conditional
  impact ordering, review-only handling, and report rules. Loaded by revise-code, revise-comments,
  revise-doc, revise-skill, and revise-test before step 1; never invoked directly.
user-invocable: false
---

# Revise Protocol — Shared Core

Every `/revise-*` leaf loads this skill before step 1 and declares the domain slots: the `vet-*`
reviewer, the target filter and no-argument file set, an impact enum (optional), the step-4 skill
loads, the verify checks, and the report template. This load runs caller→hub — the same relation as
the main thread loading `code-core` before writing code. It is not the back-edge `docs/languages.md`
forbids ("leaves never load their hub back"): that rule governs leaves the hub itself loads, and
this hub never loads or dispatches a `revise-*` skill — each one is its own entry point.

## Protocol

The leaf's numbered steps refine these rules; the rules here bind every leaf.

**Step 1 — Resolve targets and scope.** A path argument → those files, scope `full`. No argument →
the leaf's no-argument file set, scope `changed`.

**Step 2 — Dispatch the reviewer.** One **Agent** call, `subagent_type:` the leaf's `vet-*` agent.
**Do NOT set model — the agent defines its own.** Pass the file list, the review scope, and the diff
when scope is `changed`. The agent returns `### Finding N` blocks.

**Step 3 — Triage the findings** using the score the agent assigned:

- Score 0 → discard, it is a declared false positive.
- Score ≥ 75 → fix queue.
- Score below 75 → report-only queue. Do not fix these silently; they go in the report so the user
  can decide.

A leaf may declare additional routing branches that gate findings out before anything enters the fix
queue; apply those branches first.

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
"what would you fix" — stop after step 3 and report the findings. Do not apply anything. This is a
legitimate request, not an obstacle to work around.

## Report rules

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Skipping the leaf's declared triage branches → they gate findings out before the score does
