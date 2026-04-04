---
name: preflight
description: >
  Use when about to commit changes, before code review,
  or when preparing a PR for submission
argument-hint: Optional path or commit ref (defaults to changes since last push)
---

# Preflight

Automated pre-commit review with iterative fix loop.

**Core principle:** High precision over high recall. Only auto-fix verified issues (score ≥75).

## When to Use

- Before committing changes
- After completing feature work
- Preparing for code review

**Don't use:**

- On unmodified files without explicit path
- During rapid prototyping

**Announce at start:** "✈️ Preflight check initiated for [files/path]..."

**Silent until Summary:** After the start announcement, output NOTHING until Step 5's Summary
Report. No progress updates, no tool results, no "verification passed", no "no issues found". The
spinner shows progress. If you're about to output text, that's a signal to keep working
silently—user should never need to say "go on".

## Execution Sequence

**Execute steps 1-5 in order. Only stop after step 5.**

### Task Management (MANDATORY)

**At the very start**, use the **TaskCreate** tool to create ALL 5 tasks:

| # | Task subject                        | activeForm                      |
| - | ----------------------------------- | ------------------------------- |
| 1 | Setup: detect files and conventions | Detecting files and conventions |
| 2 | Cleanup: simplify and review        | Running cleanup                 |
| 3 | Review-Fix Loop                     | Scanning for issues             |
| 4 | Final verification                  | Verifying changes               |
| 5 | Generate summary report             | Generating summary              |

**As you work**, use the **TaskUpdate** tool:

- Set `status: in_progress` when starting a step
- Set `status: completed` when finishing a step

⚠️ **HARD RULE: You cannot stop while ANY task is incomplete.** If tasks 3, 4, or 5 show as
pending/in_progress, you are NOT done. Keep going.

---

### Step 1: Setup

- [ ] Get target files (path arg or git diff)
- [ ] Find CLAUDE.md conventions
- [ ] Detect languages

**Argument disambiguation:** if an argument is given:

1. If it contains `..` or `...` → commit range immediately (skip `git rev-parse`)
2. Otherwise try `git rev-parse --verify <arg> 2>/dev/null`. If it succeeds → single commit-ref
   mode. If it fails → path mode.

| Source                         | Method                                                                        |
| ------------------------------ | ----------------------------------------------------------------------------- |
| Path argument (specific file)  | Use directly — user's explicit choice, gitignore not applied                  |
| Path argument (directory/glob) | Expand files, then filter gitignored: `git check-ignore --stdin < <filelist>` |
| Commit ref (single)            | `git diff --name-only <ref>~1 <ref>`                                          |
| Commit range (`a..b`)          | `git diff --name-only <from>..<to>`                                           |
| No argument                    | Union of all sources below (deduplicated)                                     |

**No-argument file collection** — always run all four, combine and deduplicate:

1. `git diff --name-only @{push}` — committed but not yet pushed (skip if `@{push}` fails — no
   upstream)
2. `git diff --name-only` — unstaged working-tree changes
3. `git diff --cached --name-only` — staged changes
4. `git ls-files --others --exclude-standard` — untracked, non-gitignored files

If no target files are found (empty diff and no path argument), report "No changes detected" and
stop.

**CLAUDE.md Locations** (check only these, do NOT search subdirectories):

- `./CLAUDE.md` (current directory)
- `<repo-root>/CLAUDE.md`
- `~/.claude/CLAUDE.md`

→ **TaskUpdate** task 1 to `completed`. **TaskUpdate** task 2 to `in_progress`.

---

### Step 2: Cleanup

- [ ] Split target files into source files, test files, and documentation files (`.md`, `README*`,
      `CHANGELOG*`)
- [ ] Dispatch agents in parallel (single message, one **Agent** tool call per non-empty bucket):
  - **Agent A (implementation):** `model: sonnet` — "Simplify then review these implementation
    files: [list]. First apply code-distill. Then invoke `/vet-code`. If vet-code made changes,
    re-run `/vet-code` (max 3 passes total)."
  - **Agent B (tests):** `model: sonnet` — "Simplify then review these test files: [list]. First
    apply code-distill. Then invoke `/vet-test`. If vet-test made changes, re-run `/vet-test` (max 3
    passes total)."
  - **Agent C (docs):** `model: sonnet` — "Review these documentation files: [list]. Invoke
    `/vet-doc` (which routes CHANGELOG.md to `write-changelog` rules automatically). If vet-doc made
    changes, re-run `/vet-doc` (max 3 passes total)."

→ **TaskUpdate** task 2 to `completed`. **TaskUpdate** task 3 to `in_progress`. Continue silently.

---

### Step 3: Review-Fix Loop (max 3 iterations)

**This is the core of preflight.** Cleanup was just preparation.

Each iteration:

1. **Launch review agents in parallel** using **Agent** tool (single message, multiple tool calls):

   | Agent                | Focus                                                             | Model  | When                 |
   | -------------------- | ----------------------------------------------------------------- | ------ | -------------------- |
   | Bug Scanner          | Null access, off-by-one, leaks, races, logic errors               | opus   | If code files found  |
   | CLAUDE.md Compliance | Convention violations                                             | sonnet | If conventions found |
   | Doc Reviewer         | Structure, prose, accessibility, AI-writing, changelog compliance | sonnet | If doc files found   |

   **Review scope depends on input mode:**
   - **Path argument**: Review entire file(s) — flag any issues found
   - **Commit ref (single)**: Review only changed lines — `git diff <ref>~1 <ref> -- <file>`
   - **Commit range**: Review only changed lines — `git diff <from> <to> -- <file>`
   - **No argument (since last push)**: Review only changed lines — use the same diff method from
     Step 1 (`git diff @{push} -- <file>`, or the fallback if no upstream) to identify changed
     lines, flag only issues in those lines

2. **Score issues with Haiku** — dispatch **Agent** tool with `model: haiku`:

   "Score each issue on this scale and return a JSON array of `{issue, location, score}`:

   | Score    | Meaning            | Action       |
   | -------- | ------------------ | ------------ |
   | 0        | False positive     | Discard      |
   | ~25      | Unverified         | Report only  |
   | ~50      | Minor/nitpick      | Report only  |
   | **≥ 75** | Verified important | **Auto-fix** |
   | 100      | Definite, frequent | Auto-fix     |

   Issues: [paste all issues from review agents]"

3. **Fix issues with score ≥75** — dispatch agents in parallel (single message):
   - Code issues → **Agent** tool with `subagent_type: code-mend`, `model: sonnet`
   - Doc issues → **Agent** tool with `model: sonnet` — "Fix these documentation issues: [list].
     Load Skill(write-doc) and Skill(write-prose) to guide fixes. For CHANGELOG.md, load
     Skill(write-changelog) instead."

4. **Decision point:**
   - If fixes applied AND iterations < 3 → dispatch **vet agents in parallel** (single message, one
     Agent per non-empty bucket):
     - **Agent** `model: sonnet` — "Invoke `/vet-code` on these files: [list]"
     - **Agent** `model: sonnet` — "Invoke `/vet-test` on these files: [list]" (if test files)
     - **Agent** `model: sonnet` — "Invoke `/vet-doc` on these files: [list]" (if doc files) →
       repeat from iteration step 1
   - If no fixes OR iterations = 3 → proceed to Step 4

**False Positives (score = 0, discard):**

- Pre-existing issues not in your diff (no-argument mode only)
- Linter/typechecker would catch (unused imports, missing type hints, style violations)
- General quality without CLAUDE.md backing
- Silenced by ignore comments
- Stylistic prose preferences without `write-doc` rule backing

⚠️ **CHECKPOINT: Only exit loop when no fixes needed OR 3 iterations done.**

→ **TaskUpdate** task 3 to `completed`. **TaskUpdate** task 4 to `in_progress`.

---

### Step 4: Final Verification

**Skip this step if preflight made no modifications during steps 2-3** — proceed directly to Step 5.

Dispatch a single **Agent** tool call with `model: opus`:

"Review these files for correctness — bugs, logic errors, regressions. Read each file and report
issues. Return a JSON array of `{issue, location, severity}` or empty array if clean.

Files: [list of files preflight modified during steps 2-3]"

The agent reads files in its own context — do NOT pass diffs or prior state. No success claims
without fresh command output. "Should pass" is not evidence.

Issues from this step are **report-only** — no automated fix attempt. They go into the summary as
verification findings.

→ **TaskUpdate** task 4 to `completed`. **TaskUpdate** task 5 to `in_progress`.

---

### Step 5: Summary Report

Generate the final report. **This is your FIRST text output since the start announcement.**

**Report status:**

- All clear: "✅ All systems go! Cleared for commit."
- Issues fixed: "🔧 Fixed [N] issues. Ready for takeoff!"
- Issues remain: "⚠️ [N] issues need attention before departure."

**Omit empty sections.**

```markdown
# ✈️ Preflight Summary

## Files Checked

- [files]

## Iterations

- Total: [count]
- Exit reason: [no changes / max iterations]

## Issues Fixed (score >= 75)

| Issue | Location | Score | Agent |
| ----- | -------- | ----- | ----- |

## Issues Reported (score < 75)

| Issue | Location | Score | Reason Not Fixed |
| ----- | -------- | ----- | ---------------- |

## Verification Findings

| Issue | Location | Severity |
| ----- | -------- | -------- |

## Status

✅ Cleared for commit / ⚠️ Needs manual review / 🚫 Grounded — issues remain

(Verification findings always escalate to ⚠️ or 🚫)
```

→ **TaskUpdate** task 5 to `completed`. **All tasks must now show as completed.**

---

## Common Mistakes

- ❌ Sequential agent dispatch → use parallel (single message, multiple **Agent** tool calls)
- ❌ Auto-fixing linter issues → run `ruff --fix` instead
- ❌ Skipping "test files", "doc files", or "examples" → treat all files uniformly
- ❌ Fixing pre-existing issues → only fix what's in your diff (no-argument mode only)
