---
name: code-{lang}
description: >
  Use when writing any {Lang} code, regardless of perceived simplicity or prototyping context.
  Use when you think code is "just a quick script" or "types slow me down" — these are symptoms
  this skill applies. Applies to *.{ext} files.
paths: "**/*.{ext}"
user-invocable: false
model: sonnet
effort: high
---

# {Lang} Code — {Lang} Best Practices

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

## Domain Skill Detection

No overlays yet. Add a detection table here when the first library overlay is introduced.

## Mandatory Rules

<!-- Language-specific rules only. Do not restate: quick-code-is-production, comment policy,
     types-mandatory, errors-must-surface, or verification-mandatory. Those live in code-core. -->

## Pitfalls

<!-- Language-specific traps that automated tools miss -->

## Verification

**MANDATORY before completing any task:**

```bash
# Language-specific lint, type-check, and test commands go here
```

## Rationalizations That Mean You're About to Fail

<!-- Language-specific excuses for skipping the mandatory rules -->
