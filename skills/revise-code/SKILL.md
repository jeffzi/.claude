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

Review production code with the `vet-code` agent, then apply the fixes here. The agent finds; you
fix.

## Process

1. **Resolve targets and scope.**
   - Path argument → those files, scope `full`.
   - No argument → the current diff (`git diff --name-only`, `git diff --cached --name-only`,
     `git ls-files --others --exclude-standard`), scope `changed`.
   - Filter to production code. Test files belong to `/revise-test`; docs to `/revise-doc`.

2. **Dispatch the reviewer.** One **Agent** call, `subagent_type: vet-code`. **Do NOT set model —
   the agent defines its own.** Pass the file list, the review scope, and the diff when scope is
   `changed`. The agent loads `code-core` plus the language leaf and returns `### Finding N` blocks.

3. **Triage the findings** on both axes the agent emits — score gates, impact orders:
   - Score 0 → discard, it is a declared false positive.
   - Score ≥ 75 → fix queue.
   - Score below 75 → report-only queue. Do not fix these silently; they go in the report so the
     user can decide.

   Order the fix queue by impact, not by finding number: `silent-failure` → `type-safety` →
   `structure` → `clarity`. Swallowed errors get fixed even when the session is cut short; a naming
   issue waits. Within one impact tier, keep the agent's order. A finding with no Impact line is
   treated as `silent-failure` — never demoted for missing metadata.

4. **Apply the fixes.** Load `Skill(code-core)` and the matching `code-{lang}` leaf before editing —
   you are writing production code, and the leaf's rules govern the replacement as much as they
   governed the finding. Fix one finding at a time. For each, name the rule the fix satisfies.

   If a fix would change behavior rather than form, stop and surface it instead. The reviewer found
   a style or structure violation; a behavior change is a different request.

5. **Verify.** Run the project's lint, type-check, and test commands. A failing check means the fix
   is wrong — revert that fix and move it to the report-only queue with the failure attached.

6. **Report** (see below).

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "don't change anything",
"what would you fix" — stop after step 3 and report the findings. Do not apply anything. This is a
legitimate request, not an obstacle to work around.

## Report

```markdown
## Code revision: [N files]

**Checklist**: [languages and skills the agent resolved]

### Fixed

Rows in fix order — impact tier first (`silent-failure` → `type-safety` → `structure` → `clarity`).

| Issue | Location | Rule | Impact | Score |
| ----- | -------- | ---- | ------ | ----- |

### Left alone

| Issue | Location | Impact | Score | Why not fixed |
| ----- | -------- | ------ | ----- | ------------- |

### Verification

[command → pass/fail per check]
```

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Fixing score-0 findings → the agent already classified them as false positives
- ❌ Editing before loading `code-core` and the language leaf → the fix drifts from the same rules
  that produced the finding
- ❌ Silently dropping sub-75 findings → they belong in the report
- ❌ Treating `clarity` or `structure` as skippable → impact orders the queue; only the score gates
  it. Every ≥ 75 finding gets fixed, last no less than first
- ❌ Reporting fixes without running verification → "should work" is not verification
