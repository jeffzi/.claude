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

Review comments with the `vet-comments` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - Path argument → those files, scope `full`.
   - No argument → source files in the current diff, scope `changed`.

2. **Dispatch the reviewer.** One **Agent** call, `subagent_type: vet-comments`. **Do NOT set model
   — the agent defines its own.** Pass the file list, the review scope, and the diff when scope is
   `changed`. The agent loads `code-core` plus the language leaf, walks standards S1–S5, and returns
   `### Finding N` blocks.

3. **Triage the findings** using the score the agent assigned:
   - Score 0 → discard, it is a declared false positive.
   - Findings marked `out-of-scope: code bug` → never fix here. Surface them; they need `/fix`.
   - Score ≥ 75 → fix queue.
   - Score below 75 → report-only queue. Do not fix these silently; they go in the report so the
     user can decide.

4. **Apply the fixes.** Load `Skill(code-core)` and the matching `code-{lang}` leaf for the
   language's doc-comment conventions. Fix one finding at a time, naming the standard (S1–S5) each
   fix satisfies.

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

6. **Report** (see below).

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "don't change anything",
"what would you fix" — stop after step 3 and report the findings. Do not apply anything. This is a
legitimate request, not an obstacle to work around.

## Report

```markdown
## Comment revision: [N files]

**Banner shape**: [detected house shape] **Skills**: [resolved per language]

### Fixed

| Issue | Location | Standard | Score |
| ----- | -------- | -------- | ----- |

### Left alone

| Issue | Location | Score | Why not fixed |
| ----- | -------- | ----- | ------------- |

### Surfaced (out of scope)

| Issue | Location | Why |
| ----- | -------- | --- |

### Verification

[check → pass/fail, and the comments-only diff confirmation]
```

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Fixing a code bug the agent surfaced → comments-only boundary; route it to `/fix`
- ❌ Reflowing a multi-line comment while "tidying" it → preservation rule 1, no exceptions
- ❌ Deleting a comment that carries a why → rephrase in place instead
- ❌ Reporting without inspecting every diff hunk → the comments-only claim is the whole contract
