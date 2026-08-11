---
name: revise-skill
description: >
  Use when a SKILL.md needs review for activation, configuration, implementation, structure,
  security, and compliance quality — unreliable triggering, bloated body, description that doesn't match its
  triggers — and the issues fixed in place. Not for writing skills from scratch — use write-skill.
argument-hint: "[skill dir or SKILL.md path]"
# Quality floor for the slash path: adjudicating checklist findings and rewriting frontmatter is
# where cheaper tiers misread field semantics.
model: opus
effort: high
---

# Revise Skill

**Target:** $ARGUMENTS

Review a SKILL.md with the `vet-skill` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - Path argument → that skill directory or SKILL.md, scope `full`.
   - No argument → SKILL.md files appearing in `git diff --name-only`,
     `git diff --cached
     --name-only`, or `git ls-files --others --exclude-standard`, scope
     `changed`.

2. **Dispatch the reviewer.** One **Agent** call, `subagent_type: vet-skill`. **Do NOT set model —
   the agent defines its own.** Pass the target, the review scope, and the diff when scope is
   `changed`. The agent returns `### Finding N` blocks; which checklists it walks is its own
   business.

3. **Triage the findings** on both axes the agent emits — score gates, impact orders:
   - Score 0 → discard, it is a declared false positive.
   - Score ≥ 75 → fix queue.
   - Score below 75 → report-only queue. Do not fix these silently; they go in the report so the
     user can decide.

   Order the fix queue by impact, not by finding number: `security` → `activation` → `compliance` →
   `polish`. A skill that leaks secrets or never loads gets fixed even when the session is cut
   short; a naming convention waits. Within one impact tier, keep the agent's order. A finding with
   no Impact line is treated as `security` — never demoted for missing metadata.

4. **Apply the fixes.** Load `Skill(write-skill)` before editing — its design rules govern the
   replacement as much as they governed the finding, and `references/frontmatter.md` is the
   authority for any frontmatter change. Fix one finding at a time, naming the checklist item each
   fix satisfies.

   A description rewrite changes when the skill triggers. After rewriting one, re-read it against
   the skill's actual body and confirm it still describes what the skill does.

   Done when the fix queue is empty — every ≥ 75 finding applied, the last no less carefully than
   the first.

5. **Verify.**
   - The fix queue is empty, and each applied fix named its checklist item.
   - Frontmatter parses; `description` + `when_to_use` stay within the documented cap (write-skill's
     `references/frontmatter.md`, "Description budget and truncation").
   - SKILL.md stays within write-skill's line ceiling.
   - Every `Skill(name)` the body references resolves to a real skill.
   - Every `references/` file the body links exists, and no reference file is orphaned.

6. **Report** (see below).

## Review-only requests

When the user asks to review without fixing — "just review", "report only", "don't change anything",
"what would you fix" — stop after step 3 and report the findings. Do not apply anything. This is a
legitimate request, not an obstacle to work around.

## Report

```markdown
## Skill revision: [skill-name]

**Skill type**: [identified type] **Lines**: [count] / 500 **Checklists applied**: [list]

### Fixed

Rows in fix order — impact tier first (`security` → `activation` → `compliance` → `polish`).

| Issue | Location | Checklist item | Impact | Score |
| ----- | -------- | -------------- | ------ | ----- |

### Left alone

| Issue | Location | Impact | Score | Why not fixed |
| ----- | -------- | ------ | ----- | ------------- |

### Verification

[fix queue empty, description chars vs cap, line count vs ceiling, Skill() targets resolved,
reference links resolved]
```

Omit empty sections. When the agent returned `No findings.`, say so in one line and stop.

## Common mistakes

- ❌ Setting a model on the Agent call → the agent declares its own; overriding it downgrades the
  review
- ❌ Fixing score-0 findings → the agent already classified them as false positives
- ❌ Rewriting a description without re-reading the body → the new triggers stop matching the skill
- ❌ Editing frontmatter without `references/frontmatter.md` open → field semantics are easy to get
  backwards
- ❌ Silently dropping sub-75 findings → they belong in the report
- ❌ Treating `polish` or `compliance` as skippable → impact orders the queue; only the score gates
  it
