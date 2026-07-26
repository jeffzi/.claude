---
name: revise-doc
description: >
  Use when a README, guide, tutorial, reference doc, CHANGELOG, or CLAUDE.md needs review for
  structure, prose quality, accessibility, and AI-writing tells, and the issues fixed in place.
argument-hint: "[doc file or directory]"
model: opus
effort: high
---

# Revise Documentation

**Target:** $ARGUMENTS

Review documentation with the `vet-doc` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - Path argument → those files, scope `full`.
   - No argument → documentation files in the current diff (`.md`, `README*`, `CHANGELOG*`), scope
     `changed`.

2. **Dispatch the reviewer.** One **Agent** call, `subagent_type: vet-doc`. **Do NOT set model — the
   agent defines its own.** Pass the file list, the review scope, and the diff when scope is
   `changed`. The agent routes CHANGELOG.md to `write-changelog` rules and CLAUDE.md to the
   CLAUDE.md checklist automatically, and returns `### Finding N` blocks.

3. **Triage the findings** on both axes the agent emits — score gates, impact orders:
   - Score 0 → discard, it is a declared false positive.
   - Score ≥ 75 → fix queue.
   - Score below 75 → report-only queue. Do not fix these silently; they go in the report so the
     user can decide.

   Order the fix queue by impact, not by finding number: `misinformation` → `access` → `navigation`
   → `polish`. Content a reader would act on and fail gets fixed even when the session is cut short;
   a prose tell waits. Within one impact tier, keep the agent's order. A finding with no Impact line
   is treated as `misinformation` — never demoted for missing metadata.

4. **Apply the fixes.** Load `Skill(write-doc)` for structural fixes and `Skill(write-prose)` for
   sentence-level ones before editing; `Skill(write-changelog)` when the target is a CHANGELOG. Fix
   one finding at a time. For each, name the rule the fix satisfies.

   Rewriting prose is in scope. Changing what the document asserts is not — if a finding says the
   docs are factually stale, verify against the code before editing, and surface it if you cannot.

5. **Verify.** Run the project's markdown lint and spell-check where configured. Confirm every code
   example you touched still matches the API it documents, and every link you rewrote still
   resolves.

6. **Report** (see below).

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "don't change anything",
"what would you fix" — stop after step 3 and report the findings. Do not apply anything. This is a
legitimate request, not an obstacle to work around.

## Report

```markdown
## Documentation revision: [N files]

**Document types**: [type per file]

### Fixed

Rows in fix order — impact tier first (`misinformation` → `access` → `navigation` → `polish`).

| Issue | Location | Rule | Impact | Score |
| ----- | -------- | ---- | ------ | ----- |

### Left alone

| Issue | Location | Impact | Score | Why not fixed |
| ----- | -------- | ------ | ----- | ------------- |

### Verification

[lint/spell command → pass/fail]
```

For CLAUDE.md targets, add the agent's quality score line. Omit empty sections. When the agent
returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Fixing score-0 findings → the agent already classified them as false positives
- ❌ Editing prose without loading `write-prose` → the rewrite drifts from the rule that produced
  the finding
- ❌ "Fixing" a staleness finding by rewording rather than checking the code → verify first
- ❌ Silently dropping sub-75 findings → they belong in the report
- ❌ Treating `polish` or `navigation` as skippable → impact orders the queue; only the score gates
  it. Every ≥ 75 finding gets fixed, last no less than first
