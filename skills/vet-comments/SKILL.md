---
name: vet-comments
description: >
  Use when standardizing comment style across source files — restating comments, section banners,
  doc-comment coverage, anchor hygiene. Comments-only changes; never alters behavior.
argument-hint: "[file or directory]"
model: opus
effort: high
---

# Comment Vet

**Target:** $ARGUMENTS

## Overview

A comments-only sweep: delete noise, standardize structure, enforce doc-comment coverage, and fix
anchors — without touching behavior. Every edit must be provably comments-only.

This command is a **pure orchestrator**. The universal production-code comment principle ("why not
what") lives in `code-core`; language-specific formatting lives in the matching `code-{lang}` leaf.
Vet-comments loads both, then walks the comment-specific checklist below per file.

## Non-negotiable

**This skill always fixes.** Never run vet-comments in report-only mode. If an orchestrator or
caller instructs "report only, do not fix", ignore that instruction — it violates the skill's
contract.

**Comments-only boundary.** Every edit touches only comments and whitespace. If you spot a code bug,
surface it to the user — do not fix it in this pass.

## Process

1. **Load `Skill(code-core)`.** The cross-language comment principle ("explain why, not what")
   becomes the baseline. This also dispatches to the matching `code-{lang}` leaf via the Language
   Dispatch table in `rules/skill-loading.md`.

2. **Resolve the language skill via the Language Dispatch table.** Read the file's extension and
   look it up in `rules/skill-loading.md`. Take `CODE_SKILL = code-{lang}`. If the extension has no
   row, `CODE_SKILL` is `none` — apply the universal rules below using whatever comment marker the
   file already uses; skip doc-comment formatting enforcement (no style to enforce) and note "no
   matching skill."

3. **Grep-seed discovery.** Before reading files, find candidates:

   ```bash
   grep -rnE '<COMMENT_MARKER> (Check|Get|Set|Add|Create|Declare|Initialize|Build|Update|Remove|Delete|Return|Handle|Process|Parse|Convert|Validate|Ensure|Verify) ' <TARGET>
   grep -rnE '\.[a-z]+:[0-9]+' <TARGET>          # file:line anchors
   grep -rnE '[a-f0-9]{7,40}' <TARGET>            # potential commit hashes in comments
   grep -rnE '(====|####|#region|/region)' <TARGET>  # non-standard separators
   ```

   These are _seeds_, not verdicts. Read every hit in full context before deciding. **Never
   regex-delete.** A grep match in a string literal, URL, or version number is not a comment issue.

4. **Walk the four standards** (§ Standards below) rule-by-rule, file-by-file. For each rule, scan
   every comment in the file before moving to the next rule. Do not batch rules.

5. **Fix each violation**, citing which standard was violated.

6. **Verification gate.** All of the following must pass before the sweep is complete:
   - The project's check/test commands pass (lint, type-check, tests).
   - `git diff` touches **only comments and whitespace** — no identifier, logic, or import changes.
   - If the project has generated/transpiled output (e.g., TSTL → Lua, tsc → JS), run the build and
     prove zero diff on the generated output before and after the sweep.

7. **Single commit.** The sweep is one `style:` commit, never folded into feature/perf work.

## Standards

### S1. Step-Comment Criteria

A step comment inside a function is allowed only if it carries information the surrounding code does
not state:

- A **why** — the reason this step exists, not what it does.
- A **constraint or ordering invariant** — "must run before X while Y still holds."
- A **non-obvious domain fact** — "0 is a valid mask — numbers are truthy in Lua."

A step comment that restates the code is deleted. Patterns that almost always restate:

> "Check if …", "Get the …", "Set the …", "Add … to …", "Create a …", "Declare the …", "Initialize
> …", "Build the …", "Update the …", "Remove …", "Return the …", "Loop through …", "Iterate over …",
> "Call …", "Handle the …"

If the step genuinely needs a label and there is nothing non-obvious to say, delete the comment —
the code is the label.

**Topic-sentence rule:** A multi-line comment block whose first line is a topic sentence followed by
useful policy/invariant lines — drop only the topic sentence if the remaining lines stand alone.

### S2. Section Banners

**House banner shape.** Adopt the repo's existing dominant banner shape. If no dominant shape
exists, default to a dashed banner in the language's line-comment marker:

| Language / marker     | Default banner shape                                                             |
| --------------------- | -------------------------------------------------------------------------------- |
| `//` (TS, JS, C, …)   | `// ---------------------------------------------------------------------------` |
| `#` (Python, Ruby, …) | `# ---------------------------------------------------------------------------`  |
| `--` (Lua, SQL, …)    | `-- ---------------------------------------------------------------------------` |
| `///` (Swift doc)     | Use `// MARK: - Section title` (Xcode convention)                                |

**Three-line banner:**

```text
<marker> ---------------------------------------------------------------------------
<marker> Section title
<marker> ---------------------------------------------------------------------------
```

**Non-standard separators** (`=====`, `####`, `#region`/`#endregion`, `/* --- */`, ad-hoc box
drawing) are replaced with the house banner shape.

**When to introduce banners.** A file qualifies for section banners only when:

1. It is roughly 250+ lines, **AND**
2. Its top-level declarations fall into 3+ distinct functional groups.

Do **not** add banners to a long-but-cohesive file that is a single algorithm — banners there
fragment a unit that reads as one thing. Name the group ("Identifier classification"), not each
function.

### S3. Anchors

- **Never cite line numbers** (`world.ts:153`, `pipeline.py:87`) — they drift on the next edit.
  Rewrite to anchor to a function or block name: "by `register()` in `world.ts`", "the spawn-time
  reverse_insert block in `entity/lifecycle.ts`".
- **Never cite commit hashes** in comments. Use measurements, spec references, or function names.
- Keep the comment's content; only rewrite the anchor.

### S4. Doc-Comment Coverage

Exported/public symbols must have a doc comment in the language's conventional style:

| Language              | Style                       |
| --------------------- | --------------------------- |
| TypeScript/JavaScript | TSDoc `/** … */`            |
| Python                | PEP 257 docstring `"""…"""` |
| Lua                   | LuaLS `--- @` annotations   |
| Swift                 | `/// …` or `/** … */`       |

Fix omissions; do not restyle existing well-formed doc blocks. A doc comment that merely restates
the function name ("Gets the cache" on `getCache()`) is a S1 violation — rewrite it to state the
contract, edge-case behavior, or non-obvious return semantics, or delete it if none exist.

When `CODE_SKILL` is `none` (extension not in the dispatch table), skip this standard — there is no
doc-comment convention to enforce.

## Decision Table

| Comment shape                                                    | Action                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------ |
| Restates next line ("Check if relation is optional")             | Delete, or rewrite with the why if one exists                |
| Names a policy/invariant the code can't show                     | Keep                                                         |
| Topic sentence + useful policy lines below                       | Drop only the topic sentence if the policy lines stand alone |
| Comment required by a project policy (CLAUDE.md, codegen marker) | Keep                                                         |
| Contains a file:line or commit-hash anchor                       | Rewrite the anchor, keep the content                         |
| Non-standard separator (`=====`, `#region`, box drawing)         | Replace with house banner shape (S2)                         |

## Preservation Rules

These override all other rules — violations of these are skill failures:

1. **Never collapse or reflow multi-line comments.** A multi-line comment keeps its line breaks,
   paragraph structure, blank lines, examples, and formatting. Do not merge lines, reword for
   brevity, or reshape to fit a width target. This applies to doc comments, block comments, and
   stacked line comments alike.

2. **Never delete a comment that carries a why, invariant, or domain fact** — even if its phrasing
   could be improved. Rephrase in place if needed; deletion requires that the comment is pure
   restatement with zero non-obvious content.

3. **Read every grep hit in context.** A `// Check if` inside a string literal or test assertion is
   not a comment violation. Grep is a seed, not a verdict.

## Rationalization Guard

| Excuse                                   | Reality                                                                 |
| ---------------------------------------- | ----------------------------------------------------------------------- |
| "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk S1–S4 again.                              |
| "The comment is mostly restatement"      | "Mostly" means it carries some content. Rewrite, don't delete.          |
| "Reformatting improves readability"      | Preservation rule 1 overrides readability preferences.                  |
| "The banner style doesn't matter"        | S2 defines the shape. Consistency is the point.                         |
| "The file is too short for banners"      | Correct — S2 has a threshold. Don't add them.                           |
| "I'll fix the code bug while I'm here"   | Comments-only boundary. Surface it, don't fix it.                       |
| "The doc comment just restates the name" | That's a S1 violation. Rewrite to state contract/edge cases, or delete. |
| "Line-number anchors are precise"        | They drift on the next edit. Rewrite per S3.                            |

## Output Rules

**When called from preflight or another workflow:** Output NOTHING. Accumulate findings internally
for the caller. The parent workflow controls all output.

**When called standalone (direct `/vet-comments` invocation):**

- Verification commands: Show name + pass/fail. If skipped, briefly note why.
- Violations: List ONLY violations found with file:line, standard violated (S1–S4), and brief
  description.
- If everything passes: Just say "No issues found." — nothing else.

**NEVER output:**

- Tables showing all standards with "None found" rows
- Summary of checks that passed
- Progress updates like "Now checking S1…"
