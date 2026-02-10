---
name: preflight
description: Use when about to commit changes, before code review, or when preparing a PR for submission
argument-hint: Optional path (defaults to git diff)
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

**Silent until Summary:** After the start announcement, output NOTHING until Step 4's Summary
Report. No progress updates, no tool results, no "verification passed", no "no issues found".
The spinner shows progress. If you're about to output text, that's a signal to keep working
silently—user should never need to say "go on".

## Execution Sequence

**Execute steps 1-4 in order. Only stop after step 4.**

### Task Management (MANDATORY)

**At the very start**, use the **TaskCreate** tool to create ALL 4 tasks:

| # | Task subject                        | activeForm                      |
| - | ----------------------------------- | ------------------------------- |
| 1 | Setup: detect files and conventions | Detecting files and conventions |
| 2 | Cleanup: simplify and review        | Running cleanup                 |
| 3 | Review-Fix Loop                     | Scanning for issues             |
| 4 | Generate summary report             | Generating summary              |

**As you work**, use the **TaskUpdate** tool:

- Set `status: in_progress` when starting a step
- Set `status: completed` when finishing a step

⚠️ **HARD RULE: You cannot stop while ANY task is incomplete.**
If tasks 3 or 4 show as pending/in_progress, you are NOT done. Keep going.

---

### Step 1: Setup

- [ ] Get target files (path arg or git diff)
- [ ] Find CLAUDE.md conventions
- [ ] Detect languages

| Source        | Method                                                   |
| ------------- | -------------------------------------------------------- |
| Path argument | Use directly                                             |
| No argument   | `git diff --name-only` + `git diff --cached --name-only` |

**CLAUDE.md Locations** (check only these, do NOT search subdirectories):

- `./CLAUDE.md` (current directory)
- `<repo-root>/CLAUDE.md`
- `~/.claude/CLAUDE.md`

→ **TaskUpdate** task 1 to `completed`. **TaskUpdate** task 2 to `in_progress`.

---

### Step 2: Cleanup

- [ ] Invoke **Task** tool with `subagent_type: code-distill` - Reduce complexity
- [ ] Invoke **Skill** tools in parallel:
  - `skill: code-vet` - Language-specific idioms and patterns
  - `skill: test-vet` - Test file best practices (if test files present)

→ **TaskUpdate** task 2 to `completed`. **TaskUpdate** task 3 to `in_progress`. Continue silently.

---

### Step 3: Review-Fix Loop (max 3 iterations)

**This is the core of preflight.** Cleanup was just preparation.

Each iteration:

1. **Launch review agents in parallel** using **Task** tool (single message, multiple tool calls):

   | Agent                | Focus                                               | When                 |
   | -------------------- | --------------------------------------------------- | -------------------- |
   | Bug Scanner          | Null access, off-by-one, leaks, races, logic errors | Always               |
   | CLAUDE.md Compliance | Convention violations                               | If conventions found |

   **Review scope depends on input mode:**
   - **Path argument**: Review entire file(s) - flag any issues found
   - **No argument (git diff)**: Review only changed lines - flag only issues in diff

2. **Score issues with Haiku** (batch all issues together):

   | Score    | Meaning            | Action       |
   | -------- | ------------------ | ------------ |
   | 0        | False positive     | Discard      |
   | ~25      | Unverified         | Report only  |
   | ~50      | Minor/nitpick      | Report only  |
   | **≥ 75** | Verified important | **Auto-fix** |
   | 100      | Definite, frequent | Auto-fix     |

3. **Fix issues with score ≥75** using **Task** tool with `subagent_type: code-mend`

4. **Decision point:**
   - If fixes applied AND iterations < 3 → invoke **Skill** tool with `skill: code-vet` → repeat from step 1
   - If no fixes OR iterations = 3 → proceed to Step 4

**False Positives (score = 0, discard):**

- Pre-existing issues not in your diff (no-argument mode only)
- Linter/typechecker would catch (unused imports, missing type hints, style violations)
- General quality without CLAUDE.md backing
- Silenced by ignore comments

⚠️ **CHECKPOINT: Only exit loop when no fixes needed OR 3 iterations done.**

→ **TaskUpdate** task 3 to `completed`. **TaskUpdate** task 4 to `in_progress`.

---

### Step 4: Summary Report

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

## Status

✅ Cleared for commit / ⚠️ Needs manual review / 🚫 Grounded - issues remain
```

→ **TaskUpdate** task 4 to `completed`. **All tasks must now show as completed.**

---

## Common Mistakes

- ❌ Sequential agent dispatch → use parallel (single message, multiple **Task** tool calls)
- ❌ Auto-fixing linter issues → run `ruff --fix` instead
- ❌ Skipping "test files" or "examples" → treat all files uniformly
- ❌ Fixing pre-existing issues → only fix what's in your diff (no-argument mode only)
