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

  RED:
    1. Dispatch tdd-red agent with:
       - Task description (what behaviors to test -- may be a cohesive batch)
       - Language and test runner
       - Relevant test file paths
    2. Capture: test file, test name(s), failure output
    3. Verify all tests actually failed
    4. If any test PASSED_UNEXPECTEDLY:
       -> Report to user: behavior already exists
       -> Ask: skip (next behavior) or revise test scope?

  GREEN:
    5. Dispatch tdd-green agent with:
       - Test file path
       - Test name(s)
       - Failure output
       - Test command
    6. Capture: implementation files, test results
    7. Verify: all new tests pass + full suite passes
    8. If STUCK (5 failures):
       -> Report diagnostics to user
       -> Ask: adjust test, try manually, or skip?

  REFACTOR:
    9.  Split CHANGED_FILES into implementation files and test files
    10. Dispatch two agents in parallel (single message, two Agent tool calls):
        - Agent A: code-distill -> vet-code (-> vet-code again if changes) on impl files
        - Agent B: code-distill -> vet-test (-> vet-test again if changes) on test files
    11. If any fixes applied, re-run test suite to confirm tests still green

  CONTINUE:
    12. Ask user: more behaviors to implement? -> loop or exit
```

## Phase Data Contracts

Only structured data passes between phases -- never reasoning or analysis.

**RED -> GREEN:**

```text
TEST_FILE: <path>
TEST_NAME: <name(s)>
TEST_COMMAND: <command>
FAILURE_OUTPUT: <output>
```

**GREEN -> REFACTOR:**

```text
CHANGED_FILES: <list of all files modified in RED + GREEN>
```
