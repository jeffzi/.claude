---
name: revise-test
description: >
  Use when test files need review for redundancy, AAA violations, behavior-vs-implementation
  drift, and weak assertions, and the violations fixed in place.
argument-hint: "[test file or directory]"
model: opus
effort: high
---

# Revise Tests

**Target:** $ARGUMENTS

Review test files with the `vet-test` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - Path argument → those files, scope `full`.
   - No argument → the current diff (`git diff --name-only`, `git diff --cached --name-only`,
     `git ls-files --others --exclude-standard`), scope `changed`.
   - Filter to test files only. Production code belongs to `/revise-code`.

2. **Dispatch the reviewer.** One **Agent** call, `subagent_type: vet-test`. **Do NOT set model —
   the agent defines its own.** Pass the file list, the review scope, and the diff when scope is
   `changed`. The agent loads `test-core` plus the language leaves and returns `### Finding N`
   blocks.

3. **Triage the findings** on both axes the agent emits — score gates, impact orders:
   - Score 0 → discard, it is a declared false positive.
   - Score ≥ 75 → fix queue.
   - Score below 75 → report-only queue. Do not fix these silently; they go in the report so the
     user can decide.

   Order the fix queue by impact, not by finding number: `coverage` → `fragility` → `cost` →
   `clarity`. Coverage holes get fixed even when the session is cut short; a misleading name waits.
   Within one impact tier, keep the agent's order. A finding with no Impact line is treated as
   `coverage` — never demoted for missing metadata.

4. **Apply the fixes.** Load `Skill(test-core)` and the matching `test-{lang}` leaf before editing —
   you are writing tests, and the leaf's rules govern the replacement as much as they governed the
   finding. Fix one finding at a time. For each, name the rule the fix satisfies.

   Deleting a redundant test is a fix; deleting a test because it fails is not. If a finding would
   reduce coverage rather than redundancy, surface it instead of applying it.

5. **Verify.** Run the test suite. Every test must still pass, and the suite must still cover what
   it covered before. A failing suite means the fix is wrong — revert that fix and move it to the
   report-only queue with the failure attached.

6. **Report** (see below).

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "don't change anything",
"what would you fix" — stop after step 3 and report the findings. Do not apply anything. This is a
legitimate request, not an obstacle to work around.

## Report

```markdown
## Test revision: [N files]

**Checklist**: [languages and skills the agent resolved]

### Fixed

Rows in fix order — impact tier first (`coverage` → `fragility` → `cost` → `clarity`).

| Issue | Location | Rule | Impact | Score |
| ----- | -------- | ---- | ------ | ----- |

### Left alone

| Issue | Location | Impact | Score | Why not fixed |
| ----- | -------- | ------ | ----- | ------------- |

### Verification

[test command → pass/fail, test count before and after]
```

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Fixing score-0 findings → the agent already classified them as false positives
- ❌ Editing before loading `test-core` and the language leaf → the fix drifts from the same rules
  that produced the finding
- ❌ Deleting a test to make a finding go away → merging redundant tests is a fix; dropping coverage
  is not
- ❌ Silently dropping sub-75 findings → they belong in the report
- ❌ Treating `clarity` or `cost` as skippable → impact orders the queue; only the score gates it.
  Every ≥ 75 finding gets fixed, last no less than first
- ❌ Reporting fixes without re-running the suite → "should work" is not verification
