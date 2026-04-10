---
name: vet-skill
description: |
  Use when reviewing SKILL.md files for quality, structural, or security issues. Also use when a
  skill fails to trigger reliably, an agent ignores or rationalizes around rules under pressure, a
  skill description doesn't match triggering conditions, a SKILL.md is too long or bloated, or after
  writing a new skill to catch issues before deployment. Not for writing skills from scratch (use
  write-skill).
argument-hint: "[skill dir or SKILL.md path]"
model: sonnet
effort: medium
---

# Skill Review

**Target:** $ARGUMENTS

Review SKILL.md files systematically against activation, implementation, structural, security, and
compliance standards.

## How to review

1. **Read the SKILL.md** in full, including any files in references/.
2. **Identify the skill type** — discipline, technique, pattern, or reference. Load
   `Skill(write-skill)` to consult its type table. This determines which checklists apply.
3. **Run through the checklists** in `references/checklists.md`, section by section. All skills get
   activation, implementation, structure, and security. Discipline skills also get the compliance
   checklist.
4. **Invoke `write-skill`** for design guidance and remediation on any findings.
5. **Report findings** using the output format at the bottom.
6. **Apply fixes** directly unless the user asked for review-only.

## Anti-pattern detection

Flag these skill anti-patterns:

| Anti-pattern                    | What to look for                                                        |
| ------------------------------- | ----------------------------------------------------------------------- |
| Workflow summary in description | Description summarizes steps — Claude follows summary, skips body       |
| Narrative example               | Session-specific stories instead of general patterns                    |
| Multi-language dilution         | Same example in 5+ languages — mediocre quality, maintenance cost       |
| Code in flowcharts              | Implementation code inside diagrams — can't copy-paste                  |
| Generic labels                  | `helper1`, `step3`, `pattern4` — labels without semantic meaning        |
| Over-documenting known things   | Standard library usage, common patterns Claude already knows            |
| Missing boundary conditions     | No "when NOT to use" or "use X instead" routing                         |
| Orphan references               | Reference files not linked from SKILL.md body                           |
| Deep reference chains           | References that reference other references — Claude won't follow        |
| Discipline without testing      | Enforcement rules without documented pressure test results              |
| Prose delegation                | "Follow commit conventions" instead of `` Load `Skill(write-commit)` `` |
| Kitchen-sink context            | Many shell injections dumping bulk data Claude may not need             |
| Broken Skill() targets          | `Skill(name)` pointing to skills that don't exist or wrong spelling     |

## Common reviewer mistakes

- Applying the compliance checklist to non-discipline skills (technique, pattern, reference skip it)
- Flagging style preferences as important when only discipline rules warrant enforcement
- Reporting content Claude already knows as "missing" (standard library docs, common patterns)
- Treating long descriptions as critical when they're within the 1024-char limit and specific
- Flagging absence of pressure-testing evidence for technique/reference skills

## Rationalization guard

| Excuse                                                         | Reality                                                                                                            |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| "The skill works fine — no need to vet it"                     | Skills degrade silently. Vet after every substantive edit, not just on failure.                                    |
| "It's a reference skill — compliance checklist doesn't apply"  | Correct; skip compliance. But activation, implementation, structure, and security still apply to every skill type. |
| "The description is long but specific"                         | Length within limit ≠ quality. A long description can still summarize workflow — check the exact wording.          |
| "Zero findings in a mature skill"                              | Re-examine trigger quality, `Skill()` reference targets, and security before concluding zero issues.               |
| "I know this skill; I don't need to walk every checklist item" | Familiarity causes over-skip. Walk the checklist section by section; don't rely on memory.                         |

## Severity classification

- **Critical** — Skill will not trigger (broken frontmatter, missing description), security
  vulnerability (credential exposure), or exceeds 500-line limit
- **Important** — Skill triggers but may not be followed reliably (missing rationalization table for
  discipline skill, no symptoms in description, workflow summary in description)
- **Minor** — Style/convention issues (naming not verb-first, missing "when not to use" section,
  generic labels)

## Output format

Report findings as a structured list grouped by severity:

```markdown
## Skill review: [skill-name]

**Skill type**: [identified type] **Lines**: [line count] / 500

### Issues

#### Critical (blocks deployment)

- [file:line] **[category]**: Description of issue. Suggested fix or write-skill section to consult.

#### Important (should fix)

- [file:line] **[category]**: Description of issue. Suggested fix or write-skill section to consult.

#### Minor (nice to fix)

- [file:line] **[category]**: Description of issue. Suggested fix or write-skill section to consult.

### Summary

[1-2 sentence overall assessment]
```

Categories: `activation`, `implementation`, `structure`, `security`, `compliance`
