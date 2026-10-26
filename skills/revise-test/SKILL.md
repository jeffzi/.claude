---
name: revise-test
description: >
  Use when test files need review for redundancy, AAA violations, behavior-vs-implementation
  drift, weak assertions, and tests that should not exist (a dependency's behavior, fixed
  configuration or wording, a fake's own output), and the violations fixed in place. Also use when a test suite needs
  cross-file fixes — extracting shared fixtures, merging duplicate tests across files, deleting
  duplicate traversals. Not for review without fixes — dispatch vet-test, vet-test-merit, or
  vet-test-suite for a whole suite. Not for
  writing new tests — use tdd. Not for failing tests with unknown root cause — use /fix.
argument-hint: "[test file or directory]"
model: opus
effort: high
---

# Revise Tests

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, impact
ordering, review-only handling, report rules) that every step below follows.

Review test files with the `vet-test` and `vet-test-merit` agents (and `vet-test-suite` for
directory targets), then apply the fixes here. The agents find; you fix.

## Changed files (no-argument path)

```!
git diff --name-only 2>/dev/null || true
git diff --cached --name-only 2>/dev/null || true
git ls-files --others --exclude-standard 2>/dev/null || true
```

## Process

1. **Resolve targets.**
   - No argument → the changed files listed above. If the list is empty (no git repo or no changes),
     stop and ask the user for an explicit target.
   - File or directory argument → that path.
   - Filter to test files only. Production code belongs to `/revise-code`.

2. **Dispatch the reviewers.**
   - Dispatch `subagent_type: vet-test` and `subagent_type: vet-test-merit` per bucket, following
     the revise-core bucketing rule. `vet-test-merit` owns test-core § 4 and § 4a; `vet-test` the
     rest. Both report § 5 repeats, and revise-core's Merge stage joins them.
   - The suite agent is `subagent_type: vet-test-suite`; revise-core step 2 sets where it runs and
     how many times. `STATUS: WRONG_INPUT` → discard it; the per-file agents still run.

3. **Triage the findings.** Impact enum: `coverage` → `fragility` → `cost` → `clarity`. Coverage
   holes get fixed even when the session is cut short; a misleading name waits.

   Extra triage branch, before the verdict gates: a `confirmed` finding whose fix deletes a test, a
   parametrized row or an assertion goes to revise-core step 3a as `unconfirmed`. A reviewer's
   "nothing the project owns" is a claim, and a wrong one deletes the only test of a branch. Fixes
   that rename, restructure or strengthen a test route by verdict as usual.

4. **Apply the fixes.** Load `Skill(test-core)` and the matching `test-{lang}` leaf before editing —
   the leaf's rules govern the replacement as much as they governed the finding. For each, name the
   rule the fix satisfies.

   Deleting a redundant test is a fix; deleting a test because it fails is not. If a finding would
   reduce what the suite covers (not how many times it covers it), surface it instead of applying. A
   test `test-core` § 4a exempts — fixed configuration, a dependency's behavior, prose, a message's
   fixed wording, a shared helper re-checked through a caller, a fake's own output — covers nothing
   the project owns: deleting it reduces nothing, so the finding is applied, never surfaced.

   **Apply suite-agent findings first**, before per-file fixes touch the same files — extraction and
   merges reshape the preambles per-file fixes would otherwise edit twice. They are this skill's
   job, not a follow-up: a `confirmed` suite finding spanning many files is applied in this run
   (revise-core step 4), never deferred to a "dedicated pass" or a proposed plan.

   **Cross-file merges** (suite-agent findings). When the same behavior is pinned in two files:
   - Keep the pin at the level that owns the behavior — the finding's Reasoning names the file.
   - Fold assertions unique to the deleted copy into the survivor, parametrizing where the finding
     says so.
   - Delete the duplicate file or test block.

   **Fixture extraction** (suite-agent findings). Extract cloned setup (mock preambles, stub
   factories, duplicated helpers) to the project's existing shared-fixture location (e.g.
   `tests/fixtures/`).

5. **Verify.** Before applying any fix, record test file count, test count, and test LOC. After all
   fixes: run the test suite — every test passes, and the test count differs from the recorded count
   only by the tests the fix queue merged or deleted, each accounted for by a named surviving pin —
   or, for a § 4a deletion, by the § 4a rule that exempts it. A failing suite → isolate and revert
   the culprit fixes per revise-core step 5.

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

### Suite delta (when suite-agent findings were fixed)

| Metric | Before | After |
| ------ | ------ | ----- |
| Files  |        |       |
| Tests  |        |       |
| LOC    |        |       |

Fixtures created: [list or "none"]

### Verification

[test command → pass/fail, test count before and after]
```

## Common mistakes

- Fixing `false-positive` findings
- Editing before loading `test-core` and the language leaf
- Deleting a test to make a finding go away
- Applying a `confirmed` deletion without step 3a — the reviewer's verdict does not settle a
  deletion
- Treating `clarity` or `cost` as skippable — the verdict gates the queue; impact only orders it
- Reporting fixes without re-running the suite
- Skipping the `vet-test-suite` dispatch on a directory target
- Dispatching `vet-test` without `vet-test-merit` on a bucket — nobody else asks whether a test
  should exist
- Deferring `confirmed` suite-agent findings to a "separate dedicated pass" — cross-file extraction
  and merges are step 4 work, this run
- Dispatching `vet-test-suite` per bucket
- Keeping a merged test in an arbitrary file
