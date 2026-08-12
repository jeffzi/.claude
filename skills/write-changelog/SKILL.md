---
name: write-changelog
description: >
  Use when writing, reviewing, or modifying CHANGELOG.md
  files. Apply for new changelogs, release entries, or
  auditing existing changelogs against the Keep a Changelog
  standard. Not for release notes in documentation — use write-doc for that.
argument-hint: "[version or date range]"
allowed-tools: Read, Glob, Edit(CHANGELOG.md), Edit(**/CHANGELOG.md), Write(CHANGELOG.md), Write(**/CHANGELOG.md), Bash(git log:*), Bash(git tag:*), Bash(git describe:*)
---

# Changelog

[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) rules for CHANGELOG.md files. Linters
catch format; this catches judgment calls — entry curation, grouping, and readability.

## Context

- Last tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "(no tags yet)"`
- Commits since last tag:

```!
git log "$(git describe --tags --abbrev=0 2>/dev/null)..HEAD" --oneline 2>/dev/null || git log --oneline -30
```

## Rules

### Structure (S1–S8)

| #  | Rule                                                                                                 |
| -- | ---------------------------------------------------------------------------------------------------- |
| S1 | Title is `# Changelog`                                                                               |
| S2 | Preamble links to [Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/)  |
| S3 | `## [Unreleased]` exists and is the first version section                                            |
| S4 | Versions in reverse chronological order                                                              |
| S5 | Every version heading linkable: `## [x.y.z] - YYYY-MM-DD`                                            |
| S6 | Dates use ISO 8601 (`YYYY-MM-DD`) — no slashes, no regional formats                                  |
| S7 | Yanked releases: `## [x.y.z] - YYYY-MM-DD [YANKED]`                                                  |
| S8 | Reference link at bottom for every `[version]`, including `[Unreleased]: .../compare/vLATEST...HEAD` |

### Change Types (T1–T3)

| #  | Rule                                                                                  |
| -- | ------------------------------------------------------------------------------------- |
| T1 | Only: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security` — exact casing |
| T2 | Every entry under a `### Type` heading — no bare bullets under version                |
| T3 | Entries under the correct type (bug fix → `Fixed`, not `Changed`)                     |

### Entry Quality (Q1–Q5)

| #  | Rule                                                                                                                         |
| -- | ---------------------------------------------------------------------------------------------------------------------------- |
| Q1 | Curated for humans — no jargon, commit hashes, or slang                                                                      |
| Q2 | Consistent sentence-case capitalization                                                                                      |
| Q3 | Notable changes only — not every commit.                                                                                     |
| Q4 | Describe what changed for users, not implementation ("Add dark mode" not "Refactor CSS")                                     |
| Q5 | Drop entries that only affect contributors, not consumers (CI, test infra, dev scripts, internal benchmarks, doc reshuffles) |

## Process

1. **Rule-by-rule review** — one rule at a time, scoped to `$ARGUMENTS` (a version or date range)
   when supplied, otherwise the full file:
   - **(a)** S1–S8 top to bottom
   - **(b)** T1–T3 for every version section
   - **(c)** Q1–Q5 for every bullet point
2. **Report or fix, per caller mode** — every violation carries a line ref, rule ID, and fix. Edit
   in place only when the invocation requested changes; a read-only caller gets the report alone.

## Common Mistakes

| Excuse                        | Reality                                              |
| ----------------------------- | ---------------------------------------------------- |
| "I scanned and found nothing" | Scanning ≠ rule-by-rule. Go back to (a).             |
| "Format looks roughly right"  | Roughly ≠ compliant. Check every heading against T1. |
| "Entries are fine"            | Fine for devs ≠ fine for users. Check Q1 and Q4.     |
| "Missing links don't matter"  | Links are required by the spec. Check S8.            |
| "Zero violations"             | Re-check S3, S8, T1, Q1 before concluding clean.     |

## Output

List ONLY violations (line ref + description). If clean: "No issues found."

Never output rule tables with "None found" rows, passed-check summaries, or progress updates.
