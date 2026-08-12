# Summary Report — Status Vocabulary and Template

## Report status

- ✅ "All systems go! Cleared for commit." — exit gate ran and passed, nothing report-only. Never
  claim this unless step 6 actually ran and passed.
- 🔧 "Fixed [N] issues. Ready for takeoff!" — exit gate passed, fixes applied, nothing report-only
- ⚠️ "[N] issues need attention before departure." — exit gate passed, report-only findings remain
- 🚫 **BLOCKED** — entry gate red; no review performed
- 🔄 **REVERTED** — fixes failed a gate; the user chose full restore, tree is back to its entry-gate
  state
- 🚫 **HANDED OFF** — a gate is red and the user chose to keep the fixes in the tree; the report
  carries the snapshot path and the one-paste restore command
- 🚫 **GROUNDED** — exit gate red; preflight's fixes remain in the tree

## Template

**Omit empty sections.**

```markdown
# ✈️ Preflight Summary

## Files Checked

- [files, with data/asset files listed as `skipped (data/asset)`]

## Gates

| Gate       | Checkers | Tests | Result |
| ---------- | -------- | ----- | ------ |
| Entry      | [cmd]    | [cmd] | ✅/🔴  |
| Fix        | …        | …     | …      |
| Corrective | …        | …     | …      |
| Exit       | [cmd]    | [cmd] | ✅/🔴  |

(one row per gate actually run, named after its capture files — `gate-entry-*`, `gate-fix-*`,
`gate-corrective-*`, `gate-exit-*`; a gate that went red and self-recovered records
`🔴→✅ (formatter re-run)` or `🔴→✅ (gate repair)`, never a plain ✅; note here if a half was
absent — "no test suite: gates ran checkers only")

## Review Agents

| Agent | Found | Fixed | Report-only |
| ----- | ----- | ----- | ----------- |

(one row per lens dispatched in step 3 — vet-code, vet-test, vet-doc, vet-comments, bug-scanner,
distill-scanner — including lenses that returned "No findings."; plus a `claim-reviewer` row when
adjudication or fix verification ran, mapped as Found = claims sent, Fixed = `Verified`, Report-only
= `Refuted` + `Unsubstantiated`)

## Issues Fixed (score ≥ 75)

Rows ordered by impact rank, worst first.

| Issue | Location | Impact | Score | Agent |
| ----- | -------- | ------ | ----- | ----- |

## Issues Reported (not auto-fixed)

| Issue | Location | Impact | Score | Reason Not Fixed |
| ----- | -------- | ------ | ----- | ---------------- |

## Post-Fix Bugs (unresolved)

| Issue | Location | Impact | Score |
| ----- | -------- | ------ | ----- |

(Only bugs still in the delivered tree: post-corrective findings, and any post-fix finding that went
unfixed. A bug a mender introduced and the corrective round removed is internal churn — the
Corrective gate row is its only trace; the report describes the delivered tree, never the pipeline's
self-repairs.)

## Verification Findings

| Claim | Location | Verdict | Score |
| ----- | -------- | ------- | ----- |

(Failures only: `Refuted` and `Unsubstantiated` rows. A `Verified` claim never appears here — its
only trace is the claim-reviewer tally. Verification findings always escalate: while one exists the
status is never ✅ or 🔧 — ⚠️ at best, 🚫 if the exit gate is also red.)

## Status

✅ Cleared for commit / ⚠️ Needs manual review / 🚫 Blocked / 🔄 Reverted / 🚫 Handed off / 🚫
Grounded
```
