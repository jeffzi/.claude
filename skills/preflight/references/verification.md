# Fix-Claim Verification

Step 5's closing contract. Every mender report asserts issues were resolved; the gates only proved
nothing broke, and the scans only hunted new bugs. Nothing else re-reads the fix sites — this does.

## Dispatch

After the post-fix scan (and the corrective round, when one ran), dispatch one **Agent** call,
`subagent_type: claim-reviewer` (do NOT set model — the agent defines its own), with one claim per
applied fix — both rounds — whose finding came from `bug-scanner`, cites a project CLAUDE.md
convention, or was promoted via adjudication:

```text
Claim N: [issue from the finding] is now resolved at [file:line], and the surrounding code is intact
Location: [file:line]
Stated evidence: [what code-mender reported changing]
```

Skill-rule style fixes are excluded for the same reason style 50s are not adjudicated: re-checking a
style edit costs an agent and settles little; the runtime and convention claims are where a phantom
fix ships a real problem. The reviewer re-reads each location in its own context — do not pass diffs
or prior state beyond the claim text.

## Verdict routing — report-only, never a re-fix; the round cap holds

- `Verified` → the fix held. It produces NO row anywhere — not in Verification Findings (that table
  holds failures only; a Verified row there reads as an unaddressed problem and contradicts the
  status line) — its only trace is the claim-reviewer tally.
- `Refuted` (score ≥ 75) → the fix did not hold. Move the finding's row from Issues Fixed to the
  Verification Findings table.
- `Unsubstantiated` (score ≥ 75) → the fix could not be confirmed. Same move.
- Independent of the reviewer: a fix the mender itself reported as skipped or failed is never
  printed as Fixed — it moves to Issues Reported with the mender's stated reason, and needs no
  claim.
- When a row moves, adjust the per-agent tally to match: a fix that did not hold, or was skipped, is
  no longer counted as fixed for its lens. The tally is a report of outcomes, not of dispatch-time
  intentions.

## Mistakes

- ❌ Printing "Fixed" on the mender's word → qualifying fixes get the re-read; a `Refuted` claim
  moves to Verification Findings, a mender-reported skip moves to Issues Reported
- ❌ Re-fixing a refuted fix claim → verification is report-only; two edit rounds remain the cap
