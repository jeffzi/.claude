---
name: revise-comments
description: >
  Use when source-file comments need review for restatement, section-banner shape, doc-comment
  coverage, drifting line-number or commit-hash anchors, and narration of past decisions or dropped
  alternatives, and the violations fixed in place. Comments-only — never alters behavior.
argument-hint: "[file or directory]"
model: opus
effort: high
---

# Revise Comments

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, review-only
handling, report rules) that every step below follows.

Review comments with the `vet-comments` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - No argument → source files in the current diff.

2. **Dispatch the reviewer:** `subagent_type: vet-comments`. The agent loads `code-core` plus the
   language leaf and walks standards S1–S5.

3. **Triage the findings** on verdict alone — this skill declares no impact enum. One declared
   triage branch runs before the verdict gates: findings marked `out-of-scope: code bug` → never fix
   here. Surface them; they need `/fix`.

4. **Apply the fixes.** Load `Skill(code-core)` and the matching `code-{lang}` leaf for the
   language's doc-comment conventions. Name the standard (S1–S5) each fix satisfies.

   **Preservation rules bind you as they bind the agent.** Never collapse or reflow a multi-line
   comment. Never delete a comment carrying a why, invariant, or domain fact — rephrase in place. A
   comment that survives the reviewer's preservation rules is not yours to shorten.

   An S5 fix is the one that most often overreaches. Extract the constraint the narration was
   carrying and write it as an imperative; delete the block only when nothing but narration remains.
   Losing a constraint while deleting its backstory is a failed fix, not a thorough one.

5. **Verify — the comments-only gate.** All of these must hold before you report:
   - The project's lint, type-check, and test commands pass.
   - `git diff` touches **only** comments and whitespace. No identifier, logic, import, or
     formatting-of-code changes. Inspect every hunk.
   - Where the project emits generated or transpiled output, build it and confirm the output is
     byte-identical before and after.

   A diff hunk that touches code means a fix went wrong. Revert that hunk.

6. **Report** (template below).

## Report

```markdown
## Comment revision: [N files]

**Banner shape**: [detected house shape] **Skills**: [resolved per language]

### Fixed

| Issue | Location | Standard | Verdict |
| ----- | -------- | -------- | ------- |

### Left alone

| Issue | Location | Verdict | Why not fixed |
| ----- | -------- | ------- | ------------- |

### Surfaced (out of scope)

| Issue | Location | Why |
| ----- | -------- | --- |

### Verification

[check → pass/fail, and the comments-only diff confirmation]
```

## Common mistakes

- ❌ Fixing a code bug the agent surfaced → comments-only boundary; route it to `/fix`
- ❌ Reflowing a multi-line comment while "tidying" it → preservation rule 1, no exceptions
- ❌ Deleting a comment that carries a why → rephrase in place instead
- ❌ Reporting without inspecting every diff hunk → the comments-only claim is the whole contract
