# Triage — Queues, Ranking, and Adjudication

Step 4's triage contract. One orchestrator pass over every lens's output; filtering happens here and
only here — reviewers report everything.

## Queues

- Collect all `### Finding N` blocks from every lens. They share one format and one verdict enum —
  Verdict is confidence (`false-positive` / `suspected` / `unconfirmed` / `confirmed`), Impact is
  the consequence tag — so they share one queue.
- Keep a per-agent tally (found / fixed / report-only) as you go; the report's Review Agents table
  is built from it.
- Discard `false-positive` findings (list below).
- Partition: `confirmed` → fix queue; `suspected` → report-only queue; `unconfirmed` → adjudication.

**False positives (`false-positive`, discard):**

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
| vet-comments               | misdirection   | coverage     | noise      | structure   |
| bug-scanner                | corruption     | wrong-result | crash      | degradation |

An `unconfirmed` or `confirmed` finding with no Impact line is treated as rank 1 — never demoted for
missing metadata. Ranks drive the mender Severity line (rank 1–2 → high, rank 3–4 → medium) and the
report order.

## Adjudicating unconfirmed findings

`unconfirmed` means "named the rule, could not confirm the violation", and it is often a one-read
question. When `unconfirmed` findings exist from any lens, dispatch one **Agent** call,
`subagent_type: claim-reviewer` (do NOT set model — the agent defines its own), carrying one claim
per `unconfirmed` finding:

```text
Claim N: [issue from the finding] exists at [file:line]
Location: [file:line]
```

Every `unconfirmed` finding is adjudicated — no carve-out by lens or rule type. The reviewer
re-derives evidence from the files, unrestricted by the step 1 target list. Route each verdict:

- `Verified` with claim-reviewer score ≥ 75 → promote to the fix queue as `confirmed`, keeping the
  finding's original Impact tag. Promotion rides the existing fix round — adjudication never adds
  one.
- `Refuted` → discard, tallied as an adjudicated false positive.
- Otherwise → report-only; its `Reason Not Fixed` cell says "adjudicated: unsubstantiated".

`suspected` findings are never adjudicated — nothing nameable to verify. They stay report-only.

## Mistakes

- ❌ Skipping adjudication for style `unconfirmed` findings → every `unconfirmed` finding is
  adjudicated, no exceptions
- ❌ Promoting on `Unsubstantiated` → only a `Verified` verdict with claim-reviewer score ≥ 75
  promotes
- ❌ Checking the empty-fix-queue before adjudication → the check runs after; a promoted finding can
  populate an empty queue
