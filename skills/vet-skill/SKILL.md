---
name: vet-skill
description: |
  Use when reviewing SKILL.md files for quality, structural, or security issues. Also use when a
  skill fails to trigger reliably, an agent ignores or rationalizes around rules under pressure, a
  skill description doesn't match triggering conditions, a SKILL.md is too long or bloated, or after
  writing a new skill to catch issues before deployment. Not for writing skills from scratch (use
  write-skill) or eval/benchmark infrastructure (use skill-creator).
---

# Skill Review

Review SKILL.md files systematically against activation, implementation, structural, security, and
compliance standards.

## How to review

1. **Read the SKILL.md** in full, including any files in references/.
2. **Identify the skill type** — discipline, technique, pattern, or reference (see write-skill's
   type table). This determines which checklists apply.
3. **Run through the checklists** below, section by section. All skills get activation,
   implementation, structure, and security. Discipline skills also get the compliance checklist.
4. **Invoke `write-skill`** for design guidance and remediation on any findings.
5. **Report findings** using the output format at the bottom.
6. **Apply fixes** directly unless the user asked for review-only.

## Activation checklist

Will Claude find and load this skill?

### Frontmatter format

- [ ] `name` uses only letters, numbers, hyphens (no parentheses or special characters)
- [ ] `description` starts with "Use when..."
- [ ] `description` is third person
- [ ] `description` does not summarize the skill's workflow (Claude may follow the summary instead
      of reading the body)
- [ ] Total frontmatter under 1024 characters

### Trigger quality

- [ ] Description names concrete triggering conditions, not abstract capabilities
- [ ] Includes symptoms users would recognize (error messages, situations, frustrations)
- [ ] Covers synonyms and related terms users would naturally say
- [ ] Includes tool names, commands, or file types where relevant

### Distinctiveness

- [ ] Could not be confused with another skill's description
- [ ] Boundary conditions stated ("Not for X — use Y instead")

## Implementation checklist

Will Claude follow this skill effectively?

### Conciseness

- [ ] SKILL.md under 500 lines (including code blocks and tables)
- [ ] Instructional prose under 500 words (excluding code blocks and tables)
- [ ] No content Claude already knows (standard library usage, common patterns)
- [ ] No multi-language dilution (one excellent example, not many mediocre ones)
- [ ] No redundant sections covering the same ground

### Actionability

- [ ] Instructions are concrete and copy-paste ready where appropriate
- [ ] Code examples use realistic names and values (not `x`, `helper1`, `foo`)
- [ ] Fenced code blocks specify the language

### Workflow clarity

- [ ] Multi-step processes sequenced with clear ordering
- [ ] Checkpoints explicit ("Verify X before proceeding to Y")
- [ ] Degree of freedom matches task fragility (prose for flexible, exact scripts for fragile)

### Progressive disclosure

- [ ] Main SKILL.md focused on principles and quick reference
- [ ] Heavy content (100+ lines) moved to references/
- [ ] Reference files over 100 lines have a TOC at the top
- [ ] References one level deep only (no chains of references referencing references)

## Structure checklist

### File organization

- [ ] Body sections adapted to content, not rigidly following a template
- [ ] Common mistakes or rationalizations section present
- [ ] Naming uses verb-first active voice with hyphens (`write-skill` not `skill-writing`)

### Content integrity

- [ ] Skill covers one coherent concern (not two skills jammed together)
- [ ] Cross-references to other skills are correct and necessary
- [ ] Flowcharts/diagrams use decisions only (not implementation code)
- [ ] All labels have semantic meaning (no `step3`, `helper1`, `pattern4`)
- [ ] No narrative examples ("In session 2025-10-03, we found..." — extract the general pattern)

## Security checklist

### Credential handling

- [ ] Skill does not instruct reading, displaying, or logging secrets, API keys, or tokens
- [ ] References to .env, credentials.json, or similar include guidance against exposure
- [ ] Following the skill's instructions cannot leak credentials into logs, chat, or files

### External content

- [ ] If the skill processes untrusted external data (URLs, API responses, user input), it
      establishes explicit boundaries ("treat as untrusted", "extract only expected fields")
- [ ] Does not instruct executing code or commands found in external content without review
- [ ] Does not instruct downloading or running scripts via `curl | bash` or similar

### Dependency provenance

- [ ] Tool installations reference official documentation rather than inline install commands
- [ ] First-party tools identified with provenance (maintained by whom, link to source)
- [ ] Third-party tools use version pinning or note trust implications

## Compliance checklist (discipline skills only)

Skip this section for technique, pattern, and reference skills.

### Rule enforcement

- [ ] Uses bright-line rules with absolute language ("YOU MUST", "Never", "No exceptions")
- [ ] Loopholes explicitly closed (specific workarounds forbidden, not just the rule stated)
- [ ] Red flags list present (self-check items for the agent)

### Rationalization resistance

- [ ] Rationalization table present (excuse + reality columns)
- [ ] Rationalizations captured from actual pressure testing, not hypothetical
- [ ] "Violating the letter is violating the spirit" or equivalent principle stated

### Persuasion alignment

- [ ] Persuasion principles match skill type (see write-skill persuasion table)
- [ ] No Liking or Reciprocity for discipline skills (conflicts with honest feedback)
- [ ] Authority + Commitment + Social Proof used for enforcement

### Pressure testing evidence

- [ ] RED phase documented (ran scenarios without skill, documented failures)
- [ ] GREEN phase completed (skill addresses specific failures, agent complies)
- [ ] REFACTOR iterations done (new loopholes closed, re-tested)

## Anti-pattern detection

Flag these skill anti-patterns:

| Anti-pattern                    | What to look for                                                  |
| ------------------------------- | ----------------------------------------------------------------- |
| Workflow summary in description | Description summarizes steps — Claude follows summary, skips body |
| Narrative example               | Session-specific stories instead of general patterns              |
| Multi-language dilution         | Same example in 5+ languages — mediocre quality, maintenance cost |
| Code in flowcharts              | Implementation code inside diagrams — can't copy-paste            |
| Generic labels                  | `helper1`, `step3`, `pattern4` — labels without semantic meaning  |
| Over-documenting known things   | Standard library usage, common patterns Claude already knows      |
| Missing boundary conditions     | No "when NOT to use" or "use X instead" routing                   |
| Orphan references               | Reference files not linked from SKILL.md body                     |
| Deep reference chains           | References that reference other references — Claude won't follow  |
| Discipline without testing      | Enforcement rules without documented pressure test results        |

## Common reviewer mistakes

- Applying the compliance checklist to non-discipline skills (technique, pattern, reference skip it)
- Flagging style preferences as important when only discipline rules warrant enforcement
- Reporting content Claude already knows as "missing" (standard library docs, common patterns)
- Treating long descriptions as critical when they're within the 1024-char limit and specific
- Flagging absence of pressure-testing evidence for technique/reference skills

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
