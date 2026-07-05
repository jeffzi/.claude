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

  LOAD PRINCIPLES (once per session, before first RED):
    0. Load Skill(test-core). tdd-cycle will load the matching test-{lang}
       and code-{lang} skills itself via the Language Dispatch table in
       rules/skill-loading.md.

  RED-GREEN:
    1. Dispatch tdd-cycle agent (model/effort come from its frontmatter -- do not override) with:
       - Task description (what behaviors to test -- may be a cohesive batch)
       - Relevant test file paths
    2. Capture from tdd-cycle output: TEST_FILE, TEST_NAME, TEST_COMMAND,
       FULL_SUITE_COMMAND, FAILURE_OUTPUT, IMPLEMENTATION_FILES, TEST_OUTPUT, STATUS
       Then clear the cycle commit guard the agent raised:
       rm -f "$(git rev-parse --git-dir)/tdd-cycle-active"
       (while it exists, a hook blocks all git add/commit -- including yours)
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
       e. Commit the cycle (the agent NEVER commits -- you own this):
          load Skill(write-commit), then commit in TDD order:
          - stage TEST_FILE(s) only -> commit (tests first)
          - stage IMPLEMENTATION_FILES -> commit

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
        1. Dispatch code-distiller agent on the files
        2. Dispatch a general-purpose agent prompted to load Skill(vet-code) (impl track)
           or Skill(vet-test) (test track) and run it on the same files
           (vet-code/vet-test are skills, not agents -- never pass as subagent_type)
        3. If vet made changes, dispatch vet again (max 2 passes)
      - If any fixes applied, re-run FULL_SUITE_COMMAND to confirm tests still green
```

## Phase Data Contracts

Only structured data passes between phases -- never reasoning or analysis.

**Orchestrator validation:** If any required field (TEST_FILE, TEST_NAME, TEST_COMMAND,
FULL_SUITE_COMMAND, STATUS -- plus IMPLEMENTATION_FILES when STATUS is PASSED) is missing from agent
output, do NOT proceed. Re-read the output carefully. If truly absent, report to user: "agent output
missing required field: `{field}`".

**Orchestrator -> tdd-cycle:**

```text
Task description, test file paths
```

**tdd-cycle -> Orchestrator:**

The field-by-field contract (STATUS values, per-status field sets, examples) is owned by
`agents/tdd-cycle.md` § Output Format -- the single source of truth. Do not restate it here; if this
file and the agent file ever disagree, the agent file wins.

**Accumulated across all cycles (for REFACTOR):**

```text
ALL_CHANGED_FILES: <all files modified/added across all RED + GREEN cycles>
FULL_SUITE_COMMAND: <command from first RED output, retained by orchestrator>
```
