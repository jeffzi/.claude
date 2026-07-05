---
name: vet-doc
description: |
  Use when reviewing READMEs, guides, tutorials, reference docs, CHANGELOG.md, or any documentation
  file for structural issues, prose quality violations, and anti-patterns. Also use after writing
  docs to catch issues before publishing, when the user says "review the docs", "check the
  documentation", "audit the README", or when reviewing a PR that includes documentation changes.
  Not for inline code docstrings (use language-specific skills) or CLAUDE.md files (use
  claude-md-improver).
argument-hint: "[doc file or directory]"
model: opus
effort: high
---

# Documentation Review

**Target:** $ARGUMENTS

Review documentation systematically against structural and prose quality standards.

## How to review

1. **Read the document** in full before starting the review.
2. **Identify the document type** — tutorial, how-to, reference, explanation, README, CHANGELOG, or
   other. This determines which rules apply.
3. **Route by type:**
   - **CHANGELOG.md** → invoke `write-changelog` for structure and entry quality rules. Skip the
     general checklists below — `write-changelog` is the sole authority.
   - **All other docs** → continue with the checklists below.
4. **Run through the checklists** below, section by section.
5. **Invoke skills as needed** — invoke `write-doc` for structural rules, invoke `write-prose` for
   prose editing, invoke `humanizer` if AI-generated text is suspected.
6. **Report findings** using the output format at the bottom.
7. **Apply fixes** directly unless the user asked for review-only.

## Structure checklist

### Document type integrity

- [ ] Is the document type identifiable? (tutorial, how-to, reference, explanation, README,
      CHANGELOG)
- [ ] Does it follow the correct structure for its type? (see write-doc `references/doc-types.md`;
      for CHANGELOG.md see `write-changelog`)
- [ ] Are Diataxis types kept separate? Tutorials that digress into explanation, or reference that
      veers into how-to steps, are the primary structural anti-pattern.

### Audience and scope

- [ ] Is the target audience clear from the opening?
- [ ] Does the content match the audience's assumed knowledge level?
- [ ] Is the scope stated or obvious? No partial coverage without warning.

### Skimmability

- [ ] Can a reader find a specific answer within 30 seconds?
- [ ] Are headings descriptive and scannable? (not clever or vague)
- [ ] Does each paragraph lead with its topic sentence?
- [ ] Are lists used for enumeration, tables for comparison, prose for reasoning?
- [ ] Do links describe their destination? (no "click here" or "this page")

### Completeness and order

- [ ] Within its scope, does it cover everything? (the map principle — all or none)
- [ ] Are prerequisite concepts covered before they're needed? (cumulative order)
- [ ] For reference docs: is every parameter/option/flag documented with type, default, and
      description?

### Code examples

- [ ] Do code examples work? (not "almost works" — that teaches distrust)
- [ ] Are names and values realistic? (`user_email` over `x`)
- [ ] Is the language specified in fenced code blocks?
- [ ] Is output shown where helpful?
- [ ] Are non-obvious lines annotated?

### Accessibility

- [ ] Do all images have alt text?
- [ ] Are headings in proper hierarchy (no skipped levels)?
- [ ] Is information conveyed through text, not color alone?
- [ ] Are screenshots described in surrounding text?
- [ ] Are example names diverse and inclusive?

## Prose checklist

Invoke `write-prose` for the full reference. Flag these common issues:

- [ ] **Passive voice** where active would be clearer
- [ ] **Negative phrasing** where positive instructions would work
- [ ] **Vague language** — "an error" instead of "a 404 status code"
- [ ] **Needless words** — "in order to" -> "to", "due to the fact that" -> "because"
- [ ] **Misplaced modifiers** — words separated from what they modify
- [ ] **Minimizing language** — "simply", "easy", "easily", "just" (in the trivializing sense)
- [ ] **Undefined abbreviations** — acronyms used before being spelled out
- [ ] **Gendered language** — "he" as generic pronoun, non-inclusive terms
- [ ] **"See above" / "As mentioned earlier"** — readers arrive mid-page from search
- [ ] **Inconsistent terminology** — same concept called different names

## Rationalization guard

| Excuse                                                         | Reality                                                                            |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| "I read it and it seemed clear to me"                          | Clarity to the author ≠ clarity to the audience. Walk the checklists item by item. |
| "It's documentation, not code — less strict standards apply"   | Documentation bugs mislead users. Apply every checklist item.                      |
| "The AI-writing checklist doesn't apply — the author is human" | You cannot reliably determine authorship. Run the checklist regardless.            |
| "Zero issues in a well-written doc"                            | Re-examine accessibility, link text, and AI vocabulary before concluding.          |
| "The user just wants a quick pass"                             | Every pass is a full pass. Partial reviews ship undetected problems.               |

## Anti-pattern detection

Flag these documentation anti-patterns:

| Anti-pattern               | What to look for                                                     |
| -------------------------- | -------------------------------------------------------------------- |
| FAQ as primary docs        | FAQ section doing the job of tutorials or how-to guides              |
| Wall of text               | Long sections with no headings or structural breaks                  |
| Installation-first README  | README that jumps to install before explaining what/why              |
| Internal docs as user docs | Class hierarchies, implementation details exposed to users           |
| Screenshot-heavy           | Text/code shown as screenshots instead of actual text                |
| Mixed doc types            | Tutorial mid-stream switches to reference, or vice versa             |
| Stale content              | Version numbers, links, or instructions that no longer match reality |
| Overcrowded admonitions    | More than 3-4 callouts per page                                      |

## AI-writing checklist

Flag these common AI-writing tells:

- [ ] **Em dash overuse** — multiple em dashes per paragraph where commas or periods would do
- [ ] **Rule of three** — repeated three-item lists ("clarity, precision, and elegance")
- [ ] **AI vocabulary** — "delve", "landscape", "leverage", "tapestry", "multifaceted", "nuanced"
- [ ] **Promotional tone** — "powerful", "robust", "seamless", "cutting-edge" in neutral contexts
- [ ] **Negative parallelism** — "not just X, but Y" / "not merely X, but a Y" structures
- [ ] **Vague attributions** — "experts say", "many believe", "it is widely recognized"
- [ ] **Excessive conjunctives** — "Moreover", "Furthermore", "Additionally" starting every
      paragraph

## Output format

Report findings as a structured list grouped by severity:

```markdown
## Documentation review: [filename]

**Document type**: [identified type] **Audience**: [identified audience]

### Issues

#### Critical (blocks publication)

- [file:line] **[category]**: Description of issue. Suggested fix.

#### Important (should fix)

- [file:line] **[category]**: Description of issue. Suggested fix.

#### Minor (nice to fix)

- [file:line] **[category]**: Description of issue. Suggested fix.

### Summary

[1-2 sentence overall assessment]
```

Categories: `structure`, `prose`, `accessibility`, `completeness`, `accuracy`, `anti-pattern`,
`ai-writing`
