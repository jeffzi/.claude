---
name: preflight
description: >
  Use when about to commit changes, before code review,
  or when preparing a PR for submission
argument-hint: Optional path or commit ref (defaults to changes since last push)
disable-model-invocation: true
model: sonnet
effort: high
---

# Preflight

Automated pre-commit review with iterative fix loop.

**Core principle:** High precision over high recall. Only auto-fix verified issues (score ≥75).

## Context

- Argument: $ARGUMENTS
- Uncommitted changes: !`git status --porcelain`
- Commits since last push:
  !`git log @{u}..HEAD --oneline 2>/dev/null || echo "(no upstream or up to date)"`

> **Note:** Context above is orientation only. Step 1's file collection is the authoritative source
> of target files.

**Announce at start:** "✈️ Preflight check initiated for [files/path]..."

**Silent until Summary:** After the start announcement, output NOTHING until Step 5's Summary
Report. No progress updates, no tool results, no "verification passed", no "no issues found". The
spinner shows progress. If you're about to output text, that's a signal to keep working
silently—user should never need to say "continue".

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

- [ ] Disambiguate argument (commit range vs commit ref vs path — see rules below)
- [ ] Get target files (path arg or git diff)
- [ ] Find CLAUDE.md conventions (3 locations below)
- [ ] Bucket each target file using the **Language Dispatch for test-\* and code-\*** table in
      `rules/skill-loading.md` (already in session context). For each file, look up its extension:
      if the file path matches one of the test-pattern globs for that row → test files; known
      extension but not matching a test pattern → code files; `.md`, `README*`, `CHANGELOG*` → doc
      files; extension not in the table → still review: test files if the filename matches a generic
      test pattern (`test_*`, `*_test.*`, `*.test.*`, `*_spec.*`, `*Tests.*`), otherwise code files
      (`vet-code`/`vet-test` fall back to hub-only review when no dispatch row exists).

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
  - **Agent A (implementation):** `model: sonnet` — "Distill then review these implementation files:
    [list]. First load `Skill(distill-code)` and apply it to these files. Then load
    `Skill(vet-code)` and review them."
  - **Agent B (tests):** `model: sonnet` — "Distill then review these test files: [list]. First load
    `Skill(distill-code)` and apply it to these files. Then load `Skill(vet-test)` and review them."
  - **Agent C (docs):** `model: sonnet` — "Review these documentation files: [list]. Load
    `Skill(vet-doc)` and review them (it routes CHANGELOG.md to `write-changelog` rules
    automatically)."

→ Wait for all step 2 agents to return, THEN **TaskUpdate** task 2 to `completed`. **TaskUpdate**
task 3 to `in_progress`.

---

### Step 3: Review-Fix Loop (max 3 iterations)

**This is the core of preflight.** Cleanup was just preparation.

**Review scope baseline:** Step 2 agents fix files, so re-capture the diff now — re-run the step 1
collection commands; in commit-ref/range mode also include `git diff -- <target files>` to pick up
step 2's working-tree edits. Review agents get current line numbers, and cleanup edits are in scope
like any other unreviewed change.

Each iteration:

1. **Launch review agents in parallel** using **Agent** tool (single message, one call per
   applicable agent):

   **Bug Scanner** (when code files exist)
   - `subagent_type: bug-scanner` — do NOT set model, the agent defines its own
   - Prompt:
     `"Review these files for runtime correctness bugs.\n\nFiles: [code file
     list]\n\nDiff:\n[diff from step 1]\n\nScope: [full if path-argument mode,
     changed otherwise]"`

   **CLAUDE.md Compliance** (when conventions found in step 1)
   - `model: sonnet` — no subagent_type
   - Prompt:
     `"Check whether the changed code follows the project conventions below. For each
     violation, output a ### Finding N block with fields: Issue, Location, Score (0–100), Reasoning.
     Return 'No findings.' if clean. Do NOT run tests, linters, or any shell commands — this is a
     read-only review.\n\nConventions:\n[CLAUDE.md contents]\n\nFiles: [target file
     list]\n\nDiff:\n[diff from step 1]"`

   **Review scope by input mode:**
   - **Path argument**: scope = `full` — review entire file(s)
   - **Commit ref / range / no-argument**: scope = `changed` — use diff from step 1, flag only
     issues in changed lines

2. **Consolidate findings** — no agent dispatch needed:

   - Collect all `### Finding N` blocks from both agents
   - Discard findings with score 0 (false positives — see list below)
   - Partition: score ≥ 75 → fix queue; score < 75 → report-only queue

   **False Positives (score = 0, discard):**

   - Pre-existing issues not in your diff (no-argument mode only)
   - Linter/typechecker would catch (unused imports, missing type hints, style violations)
   - General quality without CLAUDE.md backing
   - Silenced by ignore comments
   - Stylistic prose preferences without `write-doc` rule backing

3. **Fix issues with score ≥ 75** — for each finding in the fix queue, dispatch one **Agent** call
   with `subagent_type: code-mender` (send all dispatches in a single parallel message — one call
   per finding). Do NOT set model. Reformat the finding into code-mender's input format:

   ```text
   Issue: [description from finding]
   Location: [file_path:line_number from finding]
   Severity: [high if score ≥ 90, medium if score ≥ 75]
   Suggested fix: [reasoning from finding]
   ```

4. **Decision point:**
   - If fixes applied AND iterations < 3 → repeat from step 3.1
   - If no fixes OR iterations = 3 → proceed to Step 4

⚠️ **CHECKPOINT: Only exit loop when no fixes needed OR 3 iterations done.**

→ **TaskUpdate** task 3 to `completed`. **TaskUpdate** task 4 to `in_progress`.

---

### Step 4: Final Verification

**Skip this step only if preflight applied no fixes AND the review-fix loop produced no report-only
findings (score < 75)** — proceed directly to Step 5. Otherwise there are claims to verify.

Two kinds of claim feed this step, and both go to `claim-reviewer`:

- **Fix claims** — every fix applied in steps 2-3 asserts an issue was resolved. Verify it held
  rather than trusting the fix report.
- **Unfixed-finding claims** — every report-only finding (score < 75) asserts an issue _exists_ but
  was too uncertain to auto-fix. Let the reviewer adjudicate whether it is real.

Dispatch a single **Agent** tool call with `subagent_type: claim-reviewer` (do NOT set model — the
agent defines its own). Pass one claim per fix and one per report-only finding:

```text
Claim N: [issue from the finding] is now resolved at [file:line], and the surrounding code is intact
Location: [file:line of the fix]
Stated evidence: [what code-mender reported changing]

Claim M: [issue from the finding] exists at [file:line]
Location: [file:line of the finding]
```

The agent re-reads each location in its own context and returns a `### Claim N` block per claim
(`Verdict: Verified | Refuted | Unsubstantiated`, `Score`, `Evidence`, `Reasoning`). Do NOT pass
diffs or prior state beyond the claim text — the agent re-derives evidence from the files.

**Consolidate the verdicts** — report-only, no automated re-fix:

- _Fix claim_ `Refuted` (≥ 75) → the fix did not hold; record as a verification finding.
- _Fix claim_ `Unsubstantiated` (≥ 75) → the fix could not be confirmed; record as a verification
  finding.
- _Unfixed-finding claim_ `Verified` (≥ 75) → the uncertain finding is real after all; escalate it
  to a verification finding so the user sees it.
- _Unfixed-finding claim_ `Refuted` → confirmed false positive; drop it.
- Anything else (verdict below score 75, or a `Verified` fix claim) → nothing to report.

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

## Issues Fixed (score ≥ 75)

| Issue | Location | Score | Agent |
| ----- | -------- | ----- | ----- |

## Issues Reported (score < 75)

| Issue | Location | Score | Reason Not Fixed |
| ----- | -------- | ----- | ---------------- |

## Verification Findings

| Claim | Location | Verdict | Score |
| ----- | -------- | ------- | ----- |

## Status

✅ Cleared for commit / ⚠️ Needs manual review / 🚫 Grounded — issues remain

(Verification findings always escalate to ⚠️ or 🚫)
```

→ **TaskUpdate** task 5 to `completed`. **All tasks must now show as completed.**

---

## Common Mistakes

- ❌ Sequential agent dispatch → use parallel (single message, multiple **Agent** tool calls)
- ❌ Single code-mender call for all findings → one **Agent** call per finding, all dispatched in
  parallel
- ❌ Auto-fixing linter issues → run the project's configured linter/formatter instead (e.g.,
  `ruff --fix`, `eslint --fix`)
- ❌ Skipping "test files", "doc files", or "examples" → treat all files uniformly
- ❌ Fixing pre-existing issues → only fix what's in your diff (no-argument mode only)
