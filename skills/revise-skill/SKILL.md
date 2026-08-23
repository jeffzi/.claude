---
name: revise-skill
description: >
  Use when a SKILL.md needs review for activation, configuration, implementation, structure,
  security, and compliance quality — unreliable triggering, bloated body, description that doesn't match its
  triggers — and the issues fixed in place. Not for writing skills from scratch — use write-skill.
argument-hint: "[skill dir or SKILL.md path]"
model: opus
effort: high
---

# Revise Skill

**Target:** $ARGUMENTS

Load `Skill(revise-core)` before step 1 — it carries the shared protocol (triage gates, impact
ordering, review-only handling, report rules) that every step below follows.

Review a SKILL.md with the `vet-skill` agent, then apply the fixes here. The agent finds; you fix.

## Process

1. **Resolve targets and scope.**
   - Path argument → that skill directory or SKILL.md.
   - No argument → SKILL.md files appearing in `git diff --name-only`,
     `git diff --cached
     --name-only`, or `git ls-files --others --exclude-standard`.

2. **Dispatch the reviewer:** `subagent_type: vet-skill`. Pass the target; which checklists the
   agent walks is its own business.

3. **Triage the findings.** Impact enum: `security` → `activation` → `compliance` → `polish`. A
   skill that leaks secrets or never loads gets fixed even when the session is cut short; a naming
   convention waits.

4. **Apply the fixes.** Load `Skill(write-skill)` before editing — its design rules govern the
   replacement as much as they governed the finding, and `references/frontmatter.md` is the
   authority for any frontmatter change. Name the checklist item each fix satisfies.

   A description rewrite changes when the skill triggers. After rewriting one, re-read it against
   the skill's actual body and confirm it still describes what the skill does.

5. **Verify.**
   - The fix queue is empty, and each applied fix named its checklist item.
   - Frontmatter parses; `description` + `when_to_use` stay within the documented cap (write-skill's
     `references/frontmatter.md`, "Description budget and truncation").
   - SKILL.md stays within write-skill's line ceiling.
   - Every `Skill(name)` the body references resolves to a real skill.
   - Every `references/` file the body links exists, and no reference file is orphaned.

6. **Report** (template below).

## Report

```markdown
## Skill revision: [skill-name]

**Skill type**: [identified type] **Lines**: [count] / 500 **Checklists applied**: [list]

### Fixed

| Issue | Location | Checklist item | Impact | Verdict |
| ----- | -------- | -------------- | ------ | ------- |

### Left alone

| Issue | Location | Impact | Verdict | Why not fixed |
| ----- | -------- | ------ | ------- | ------------- |

### Verification

[fix queue empty, description chars vs cap, line count vs ceiling, Skill() targets resolved,
reference links resolved]
```

## Common mistakes

- Fixing `false-positive` findings
- Rewriting a description without re-reading the body
- Editing frontmatter without `references/frontmatter.md` open
- Treating `polish` or `compliance` as skippable — the verdict gates the queue; impact only orders
  it
