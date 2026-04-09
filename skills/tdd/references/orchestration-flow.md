# Orchestration Flow

**Load this reference when:** dispatching TDD agents or running the RED-GREEN-REFACTOR loop.

## Table of Contents

- [Entry Point](#entry-point)
- [RED-GREEN-REFACTOR Loop](#red-green-refactor-loop)
- [Phase Data Contracts](#phase-data-contracts)

## Entry Point

When `/tdd` is invoked, determine the entry point before doing anything else:

- **Plan mode is active** -- Write plan tasks describing behaviors. Each task ends with "Use `/tdd`
  for implementation." Do NOT dispatch agents from plan mode.
- **Multiple behaviors, no plan yet** -- Load `/write-plan` and create a plan first. Do NOT dispatch
  agents until the plan is approved and you're executing a specific task.
- **Single behavior or executing a plan task** -- Proceed to the RED-GREEN-REFACTOR loop below.

## RED-GREEN-REFACTOR Loop

```text
LOOP (one behavior group per cycle):

  RESOLVE SKILLS (once per session, before first RED):
    0. Load Skill(resolve-lang-skills). Derive lang from test file extension.
       Compute TEST_SKILL = test-{lang}, CODE_SKILL = code-{lang}.
       Read project config once for overlays; prepend active overlays.
       Cache — reuse for all subsequent cycles.

  RED-GREEN:
    1. Dispatch tdd-cycle agent (model: sonnet, effort: high) with:
       - Task description (what behaviors to test -- may be a cohesive batch)
       - Relevant test file paths
       - TEST_SKILL: <resolved value>
       - CODE_SKILL: <resolved value>
    2. Capture from tdd-cycle output: TEST_FILE, TEST_NAME, TEST_COMMAND,
       FULL_SUITE_COMMAND, FAILURE_OUTPUT, IMPLEMENTATION_FILES, TEST_OUTPUT, STATUS
    3. Handle non-PASSED statuses:
       - PASSED_UNEXPECTEDLY -> behavior already exists; report to user;
         ask: skip (next behavior) or revise test scope?
       - STUCK + PHASE: RED -> test writing failed; report diagnostics to user
       - STUCK + PHASE: GREEN -> implementation failed; report diagnostics to user;
         ask: adjust test, try manually, or skip?
       - TEST_FLAWED -> report REASON + EVIDENCE to user;
         ask: fix test manually or revise scope?
    4. If STATUS is PASSED:
       a. Inspect FAILURE_OUTPUT -- confirm it shows expected failure (feature missing, not typo)
       b. Run TEST_COMMAND yourself -- verify specific tests pass
       c. Run FULL_SUITE_COMMAND yourself -- verify full suite passes (no regressions)
       d. If verification fails -> report to user; do not proceed

  CONTINUE:
    5. Ask user: more behaviors to implement? -> loop or exit

END LOOP

REFACTOR (once, after last cycle):
  10. Compute total insertions across all files modified/added during this /tdd
      invocation: git diff --stat
  11. If < 50 insertions: skip REFACTOR, log "REFACTOR skipped: <N> lines"
  12. If >= 50 insertions:
      - Split all changed files into implementation files and test files
      - Run two tracks in parallel. For each track:
        1. Dispatch code-distill agent (model: sonnet, effort: medium) on the files
        2. Dispatch vet-code (impl track) or vet-test (test track) on the same files (model: sonnet, effort: medium)
        3. If vet made changes, dispatch vet again (max 2 passes)
      - If any fixes applied, re-run FULL_SUITE_COMMAND to confirm tests still green
```

## Phase Data Contracts

Only structured data passes between phases -- never reasoning or analysis.

**Orchestrator validation:** If any required field (TEST_FILE, TEST_NAME, TEST_COMMAND,
FULL_SUITE_COMMAND, STATUS) is missing from agent output, do NOT proceed. Re-read the output
carefully. If truly absent, report to user: "agent output missing required field: `{field}`".

**Orchestrator -> tdd-cycle:**

```text
Task description, test file paths, TEST_SKILL, CODE_SKILL
```

**tdd-cycle -> Orchestrator:**

```text
STATUS: PASSED | STUCK | PASSED_UNEXPECTEDLY | TEST_FLAWED
PHASE: RED | GREEN      (only when STATUS is STUCK)
TEST_FILE: <path>
TEST_NAME: <name(s)>
TEST_COMMAND: <command>
FULL_SUITE_COMMAND: <command>
FAILURE_OUTPUT: <output from RED phase>     (prefixed with "SKILL_MISSING: <name>" if a listed skill was not found)
IMPLEMENTATION_FILES: <files modified>   (only when STATUS is PASSED)
TEST_OUTPUT: <output from GREEN phase>   (only when STATUS is PASSED)
```

**Accumulated across all cycles (for REFACTOR):**

```text
ALL_CHANGED_FILES: <all files modified/added across all RED + GREEN cycles>
FULL_SUITE_COMMAND: <command from first RED output, retained by orchestrator>
```
