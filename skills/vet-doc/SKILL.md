---
name: vet-doc
description: |
  Use when reviewing READMEs, guides, tutorials, reference docs, CHANGELOG.md, CLAUDE.md, or any
  documentation file for structural issues, prose quality violations, and anti-patterns. Also use
  after writing docs to catch issues before publishing, when the user says "review the docs", "check
  the documentation", "audit the README", "audit CLAUDE.md", "improve CLAUDE.md", or when reviewing
  a PR that includes documentation changes. Not for inline code docstrings (use language-specific
  skills).
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
   - **CLAUDE.md** (including `.claude.local.md`, `.claude.md`) → run the CLAUDE.md checklist below.
     Skip the general structure/prose checklists — CLAUDE.md files have their own quality criteria.
     Still run the AI-writing checklist.
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

## CLAUDE.md checklist

When the target is a CLAUDE.md file (or `.claude.local.md`, `.claude.md`), use this checklist
instead of the general structure/prose checklists. Read `references/claude-md-quality.md` for
scoring rubric, templates, and update guidelines.

### Discovery

Before reviewing a single file, find all CLAUDE.md files in the repository:

```bash
find . -name "CLAUDE.md" -o -name ".claude.md" -o -name ".claude.local.md" 2>/dev/null | head -50
```

Review each file individually, but flag duplication or conflicts across files.

### Quality criteria

Score each file against six criteria (see `references/claude-md-quality.md` for point weights):

- [ ] **Commands/workflows** — are build, test, lint, dev commands documented and copy-paste ready?
- [ ] **Architecture clarity** — can Claude understand the codebase structure from this file? Key
      directories, module relationships, entry points.
- [ ] **Non-obvious patterns** — are gotchas, quirks, workarounds, and "why we do it this way"
      captured?
- [ ] **Conciseness** — is every line earning its place? No filler, no restating obvious code, no
      redundancy with code comments.
- [ ] **Currency** — do commands work, do file paths exist, does the tech stack description match
      reality? Cross-reference against the actual codebase.
- [ ] **Actionability** — are instructions executable? Commands copy-paste ready, paths real, steps
      concrete — not vague or theoretical.

### Common issues

- [ ] Commands that would fail (wrong paths, missing dependencies, renamed scripts)
- [ ] References to deleted or renamed files/directories
- [ ] Copy-paste from templates without project-specific customization
- [ ] Generic best practices not specific to this project ("always write tests", "use meaningful
      names")
- [ ] Verbose explanations where a one-liner suffices
- [ ] Obvious code info restated ("UserService handles user operations")
- [ ] One-off fixes documented that are unlikely to recur
- [ ] `TODO` items never completed
- [ ] Duplicate information across multiple CLAUDE.md files in the same repo

### Output for CLAUDE.md reviews

Use the standard output format below, but replace `**Document type**` with `**CLAUDE.md type**`
(root, package, local, global) and add a quality score line:

```text
**Quality score**: XX/100 (Grade: A/B/C/D/F)
```

When proposing updates, show diffs with a "Why this helps" line for each change. See
`references/claude-md-quality.md` for update guidelines and templates by project type.

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

| Anti-pattern                | What to look for                                                     |
| --------------------------- | -------------------------------------------------------------------- |
| FAQ as primary docs         | FAQ section doing the job of tutorials or how-to guides              |
| Wall of text                | Long sections with no headings or structural breaks                  |
| Installation-first README   | README that jumps to install before explaining what/why              |
| Internal docs as user docs  | Class hierarchies, implementation details exposed to users           |
| Screenshot-heavy            | Text/code shown as screenshots instead of actual text                |
| Mixed doc types             | Tutorial mid-stream switches to reference, or vice versa             |
| Stale content               | Version numbers, links, or instructions that no longer match reality |
| Overcrowded admonitions     | More than 3-4 callouts per page                                      |
| Template boilerplate        | CLAUDE.md with placeholder sections not customized for the project   |
| Generic advice in CLAUDE.md | Universal best practices instead of project-specific context         |
| Verbose CLAUDE.md           | Paragraphs where a one-liner would do — context window is precious   |
| Obvious restated            | CLAUDE.md documenting what class/function names already say          |

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
