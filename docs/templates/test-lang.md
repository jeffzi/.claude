---
name: test-{lang}
description: >
  Use when writing or reviewing {Lang} tests with {runner}. Applies to {test-file-patterns}.
user-invocable: false
---

# {Lang} Testing with {Runner}

**This skill extends `Skill(test-core)`.** `test-core` is the primary entry point; this skill is
loaded by `test-core` based on the rules-file dispatch table.

**Also apply:** `code-{lang}` rules when reviewing production code alongside tests. Exception: test
functions typically do not need return type annotations.

## Domain Skill Detection

No overlays yet. Add a detection table here when the first library overlay is introduced.

## Mandatory Rules

<!-- Language/runner-specific rules only. Do not restate: AAA, test-behavior-not-implementation,
     isolation/determinism, merge rules, parametrize-over-loops, never-test-private. Those live
     in test-core. -->

## Verification

**MANDATORY before completing any task:**

```bash
# Language-specific test runner commands go here
```
