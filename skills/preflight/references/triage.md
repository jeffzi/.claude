# Triage — Queues, Ranking, and Adjudication

Step 4's triage contract. One orchestrator pass over every lens's output; filtering happens here and
only here — reviewers report everything.

## Queues

- Collect all `### Finding N` blocks from every lens. They share one format and one scoring rubric —
  Score is confidence on the five-value scale (0/25/50/80/100), Impact is the consequence tag — so
  they share one queue.
- Keep a per-agent tally (found / fixed / report-only) as you go; the report's Review Agents table
  is built from it.
- Discard findings with score 0 (false positives — list below).
- Partition: score ≥ 75 → fix queue; 0 < score < 75 → report-only queue.

**False positives (score = 0, discard):**

- Pre-existing issues outside the diff (when scope is `changed`)
- Linter/typechecker would catch (unused imports, missing type hints, style violations) — the gates
  already enforce these
- General quality without CLAUDE.md backing
- Silenced by ignore comments
- Stylistic prose preferences without `write-doc` rule backing

## Impact ranking

Rank each finding's Impact tag by its position in the emitting lens's enum — rank 1 is worst. The
enums are reproduced here so no agent definition needs consulting:

| Lens                       | Rank 1         | Rank 2       | Rank 3     | Rank 4      |
| -------------------------- | -------------- | ------------ | ---------- | ----------- |
| vet-code / distill-scanner | silent-failure | type-safety  | structure  | clarity     |
| vet-test                   | coverage       | fragility    | cost       | clarity     |
| vet-doc                    | misinformation | access       | navigation | polish      |
| bug-scanner                | corruption     | wrong-result | crash      | degradation |

A finding ≥ 50 with no Impact line is treated as rank 1 — never demoted for missing metadata. Ranks
drive the mender Severity line (rank 1–2 → high, rank 3–4 → medium) and the report order.

## Adjudicating uncertain claims

A 50 means "named it, could not confirm it", and it is often a one-read question. When the
report-only queue holds 50s from `bug-scanner`, or vet-lens 50s whose named rule is a project
CLAUDE.md convention (factual applicability questions — is this file generated, does the exemption
apply), dispatch one **Agent** call, `subagent_type: claim-reviewer` (do NOT set model — the agent
defines its own), carrying one claim per such finding:

```text
Claim N: [issue from the finding] exists at [file:line]
Location: [file:line]
```

Only these qualify: factual claims a fresh context can settle. A vet-lens 50 citing a skill rule
asserts an uncertain style judgment — re-adjudicating style costs an agent and settles nothing; it
stays report-only. The reviewer re-derives evidence from the files, unrestricted by the step 1
target list. Route each verdict:

- `Verified` with score ≥ 75 → promote to the fix queue at score 80, keeping the finding's original
  Impact tag. Promotion rides the existing fix round — adjudication never adds one.
- `Refuted` → discard, tallied as an adjudicated false positive.
- `Unsubstantiated`, or any verdict scored below 75 → stays report-only; its `Reason Not Fixed` cell
  says "adjudicated: unsubstantiated".

## Mistakes

- ❌ Adjudicating style 50s → only `bug-scanner` 50s and convention-cited 50s go to `claim-reviewer`
- ❌ Promoting on `Unsubstantiated` → only a `Verified` verdict ≥ 75 promotes, and only to 80
- ❌ Checking the empty-fix-queue before adjudication → the check runs after; a promoted finding can
  populate an empty queue
