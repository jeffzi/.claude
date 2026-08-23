---
name: revise-code
description: >
  Use when production code needs review against language idiom, typing, and structural rules a
  linter misses, and the violations fixed in place. Not for runtime correctness bugs — use /fix.
argument-hint: "[file or directory]"
model: opus
effort: high
---

# Revise Code

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, impact
ordering, review-only handling, report rules) that every step below follows.

Review production code with the `vet-code` agent, then apply the fixes here. The agent finds; you
fix.

## Process

1. **Resolve targets and scope.**
   - No argument → the current diff (`git diff --name-only`, `git diff --cached --name-only`,
     `git ls-files --others --exclude-standard`).
   - Filter to production code. Test files belong to `/revise-test`; docs to `/revise-doc`.

2. **Dispatch the reviewer:** `subagent_type: vet-code`. The agent loads `code-core` plus the
   language leaf.

3. **Triage the findings.** Impact enum: `silent-failure` → `type-safety` → `structure` → `clarity`.
   Swallowed errors get fixed even when the session is cut short; a naming issue waits.

4. **Apply the fixes.** Load `Skill(code-core)` and the matching `code-{lang}` leaf before editing —
   you are writing production code, and the leaf's rules govern the replacement as much as they
   governed the finding. For each, name the rule the fix satisfies.

   If a fix would change behavior rather than form, stop and surface it instead. The reviewer found
   a style or structure violation; a behavior change is a different request.

5. **Verify.** Run the project's lint, type-check, and test commands. A failing check means the fix
   is wrong — revert that fix and move it to the report-only queue with the failure attached.

6. **Report** (template below).

## Report

```markdown
## Code revision: [N files]

**Checklist**: [languages and skills the agent resolved]

### Fixed

| Issue | Location | Rule | Impact | Verdict |
| ----- | -------- | ---- | ------ | ------- |

### Left alone

| Issue | Location | Impact | Verdict | Why not fixed |
| ----- | -------- | ------ | ------- | ------------- |

### Verification

[command → pass/fail per check]
```

## Common mistakes

- Fixing `false-positive` findings
- Editing before loading `code-core` and the language leaf
- Applying a fix that changes behavior instead of surfacing it
- Treating `clarity` or `structure` as skippable — the verdict gates the queue; impact only orders
  it
- Reporting fixes without running lint, type-check, and tests
