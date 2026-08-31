---
name: revise-code
description: >
  Use when production code needs review against language idiom, typing, and structural rules a
  linter misses, and the violations fixed in place. Also use when a codebase needs cross-file
  fixes — extracting reimplemented helpers into one module, merging overflow modules, rewiring
  bypassed seams. Not for codebase review without fixes — dispatch vet-codebase. Not for runtime
  correctness bugs — use /fix.
argument-hint: "[file or directory]"
# opus/high: adjudicates cross-file extractions and behavior-change calls across parallel
# reviewer dispatches — a cheaper tier mis-triages the behavior-change guard
model: opus
effort: high
---

# Revise Code

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, impact
ordering, review-only handling, report rules) that every step below follows.

Review production code with the `vet-code` agent (and `vet-codebase` for directory targets), then
apply the fixes here. The agents find; you fix.

## Changed files (no-argument path)

```!
git diff --name-only 2>/dev/null
git diff --cached --name-only 2>/dev/null
git ls-files --others --exclude-standard 2>/dev/null
```

## Process

1. **Resolve targets and scope.**
   - No argument → the changed files listed above.
   - File or directory argument → that path.
   - Filter to production code. Test files belong to `/revise-test`; docs to `/revise-doc`.

2. **Dispatch the reviewers.**
   - Dispatch `subagent_type: vet-code` per bucket, following the revise-core bucketing rule. The
     agent loads `code-core` plus the language leaf.
   - **Directory targets only:** also dispatch exactly one `subagent_type: vet-codebase` with the
     whole directory, scope `full` — never one per bucket: cross-file duplication crosses
     directories, and the codebase agent scales by inventory, not by reading. It joins the same
     parallel message. `STATUS: WRONG_INPUT` → discard it; the per-file agent still runs.

3. **Triage the findings.** Impact enum: `silent-failure` → `type-safety` → `structure` → `clarity`.
   Swallowed errors get fixed even when the session is cut short; a naming issue waits.

4. **Apply the fixes.** Load `Skill(code-core)` and the matching `code-{lang}` leaf before editing —
   you are writing production code, and the leaf's rules govern the replacement as much as they
   governed the finding. For each, name the rule the fix satisfies.

   If a fix would change behavior rather than form, stop and surface it instead. The reviewer found
   a style or structure violation; a behavior change is a different request.

   **Apply codebase-agent findings first**, before per-file fixes touch the same files — extractions
   and module merges reshape the code per-file fixes would otherwise edit twice. They are this
   skill's job, not a follow-up: a `confirmed` cross-file finding spanning many files is applied in
   this run, never deferred to a "dedicated pass" or a proposed plan. The behavior-change guard
   above still gates each one: helper extraction and overflow-module merges preserve behavior and
   are applied (the finding's Reasoning names the module the single implementation lives in);
   unifying divergent error conventions or rewiring a bypassed seam changes behavior — surface those
   instead.

5. **Verify.** Run the project's lint, type-check, and test commands. A failing check means the fix
   is wrong — revert that fix and move it to the report-only queue with the failure attached.

   For each applied cross-file finding, additionally Grep the tree for the extracted symbol,
   constant, or merged module's name: zero definitions survive outside the module the finding's
   Reasoning named, and every former definition site now imports it. A leftover copy passes lint,
   type-check, and tests — only the count proves the extraction landed.

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

### Cross-file fixes (when codebase-agent findings were fixed)

| Finding | Surviving module | Call sites rewired |
| ------- | ---------------- | ------------------ |

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
- Skipping the `vet-codebase` dispatch on a directory target, or dispatching it per bucket
- Deferring `confirmed` cross-file findings to a "separate dedicated pass" — extraction and merges
  are step 4 work, this run
- Applying an error-convention or seam-rewiring fix instead of surfacing it — those change behavior
