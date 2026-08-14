---
name: revise-test
description: >
  Use when test files need review for redundancy, AAA violations, behavior-vs-implementation
  drift, and weak assertions, and the violations fixed in place. Not for writing new tests — use
  tdd. Not for failing tests with unknown root cause — use /fix.
argument-hint: "[test file or directory]"
model: opus
effort: high
---

# Revise Tests

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, impact
ordering, review-only handling, report rules) that every step below follows.

Review test files with the `vet-test` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - No argument → the current diff (`git diff --name-only`, `git diff --cached --name-only`,
     `git ls-files --others --exclude-standard`).
   - Filter to test files only. Production code belongs to `/revise-code`.

2. **Dispatch the reviewer:** `subagent_type: vet-test`. The agent loads `test-core` plus the
   language leaves.

3. **Triage the findings.** Impact enum: `coverage` → `fragility` → `cost` → `clarity`. Coverage
   holes get fixed even when the session is cut short; a misleading name waits.

4. **Apply the fixes.** Load `Skill(test-core)` and the matching `test-{lang}` leaf before editing —
   you are writing tests, and the leaf's rules govern the replacement as much as they governed the
   finding. For each, name the rule the fix satisfies.

   Deleting a redundant test is a fix; deleting a test because it fails is not. If a finding would
   reduce coverage rather than redundancy, surface it instead of applying it.

5. **Verify.** Run the test suite. Every test must still pass, and the suite must still cover what
   it covered before. A failing suite means the fix is wrong — revert that fix and move it to the
   report-only queue with the failure attached.

6. **Report** (template below).

## Report

```markdown
## Test revision: [N files]

**Checklist**: [languages and skills the agent resolved]

### Fixed

| Issue | Location | Rule | Impact | Verdict |
| ----- | -------- | ---- | ------ | ------- |

### Left alone

| Issue | Location | Impact | Verdict | Why not fixed |
| ----- | -------- | ------ | ------- | ------------- |

### Verification

[test command → pass/fail, test count before and after]
```

## Common mistakes

- ❌ Fixing `false-positive` findings → the agent already classified them as false positives
- ❌ Editing before loading `test-core` and the language leaf → the fix drifts from the same rules
  that produced the finding
- ❌ Deleting a test to make a finding go away → merging redundant tests is a fix; dropping coverage
  is not
- ❌ Silently dropping `suspected` or unsubstantiated findings → they belong in the report
- ❌ Treating `clarity` or `cost` as skippable → impact orders the queue; only the verdict gates it.
  Every `confirmed` finding gets fixed, last no less than first
- ❌ Reporting fixes without re-running the suite → "should work" is not verification
