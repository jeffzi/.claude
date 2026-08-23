---
name: revise-doc
description: >
  Use when a README, guide, tutorial, reference doc, CHANGELOG, or CLAUDE.md needs review for
  structure, prose quality, accessibility, and AI-writing tells, and the issues fixed in place.
  Not for creating or structuring new documentation — use write-doc.
argument-hint: "[doc file or directory]"
model: opus
effort: high
---

# Revise Documentation

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, impact
ordering, review-only handling, report rules) that every step below follows.

Review documentation with the `vet-doc` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - No argument → documentation files in the current diff (`.md`, `README*`, `CHANGELOG*`).

2. **Dispatch the reviewer:** `subagent_type: vet-doc`. The agent routes CHANGELOG.md to
   `write-changelog` rules and CLAUDE.md to `references/claude-md-quality.md` automatically.

3. **Triage the findings.** Impact enum: `misinformation` → `access` → `navigation` → `polish`.
   Content a reader would act on and fail gets fixed even when the session is cut short; a prose
   tell waits.

4. **Apply the fixes.** Load `Skill(write-doc)` for structural fixes and `Skill(write-prose)` for
   sentence-level ones before editing; `Skill(write-changelog)` when the target is a CHANGELOG. For
   each, name the rule the fix satisfies.

   Rewriting prose is in scope. Changing what the document asserts is not — if a finding says the
   docs are factually stale, verify against the code before editing, and surface it if you cannot.

5. **Verify.** Run the project's markdown lint and spell-check where configured. Confirm every code
   example you touched still matches the API it documents, and every link you rewrote still
   resolves.

6. **Report** (template below).

## Report

```markdown
## Documentation revision: [N files]

**Document types**: [type per file]

### Fixed

| Issue | Location | Rule | Impact | Verdict |
| ----- | -------- | ---- | ------ | ------- |

### Left alone

| Issue | Location | Impact | Verdict | Why not fixed |
| ----- | -------- | ------ | ------- | ------------- |

### Verification

[lint/spell command → pass/fail]
```

For CLAUDE.md targets, add the agent's quality score line.

## Common mistakes

- Fixing `false-positive` findings
- Editing prose without loading `write-prose`
- "Fixing" a staleness finding by rewording rather than checking the code
- Treating `polish` or `navigation` as skippable — the verdict gates the queue; impact only orders
  it
