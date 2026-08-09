# Orchestration Flow

**Load this reference when:** dispatching TDD agents or running the RED-GREEN-REFACTOR loop.

## Table of Contents

- [Entry Point](#entry-point)
- [Wave Planning](#wave-planning)
- [RED-GREEN-REFACTOR Loop](#red-green-refactor-loop)
- [Phase Data Contracts](#phase-data-contracts)

## Entry Point

When `/tdd` is invoked, determine the entry point before doing anything else:

- **Plan mode is active** -- Write plan tasks describing behaviors. Each task ends with "Use `/tdd`
  for implementation." Do NOT dispatch agents from plan mode.
- **Multiple behaviors, no plan yet** -- Load `Skill(write-plan)` and create a plan first. Do NOT
  dispatch agents until the plan is approved and you're executing a specific task.
- **Single behavior or executing a plan task** -- Proceed to the RED-GREEN-REFACTOR loop below.

## Wave Planning

Before the loop, partition the task's behavior groups into **waves** — from the behavior list alone,
never from file contents (reading files to plan waves is the same violation as reading them to
batch):

- Two groups are **independent** when neither consumes anything the other introduces (no new
  function, type, or module from one is used by the other) AND their test files and implementation
  areas are disjoint. Independent groups share a wave.
- A group that consumes another group's output goes in a **later wave** — its GREEN phase needs the
  producer's code on disk (verified, not committed — commits happen after REFACTOR).
- Unsure whether two groups are independent → serialize them. A wasted wave costs one dispatch
  round; two agents editing the same file costs a corrupted cycle.

A wave of one is the ordinary serial case; the loop below is identical for it.

## RED-GREEN-REFACTOR Loop

```text
LOOP (one wave per iteration; a wave = one or more independent behavior groups):

  RED-GREEN:
    0. The dispatch below is the wave's FIRST tool call. No Read/Bash/Glob/Grep between
       the task's behavior list and the Agent calls: language detection (e.g. TSTL markers)
       is tdd-cycle's own hub dispatch, and every suite run happens in step 4, after the
       agents return. Announcing the dispatch is not the dispatch. Wave planning uses the
       behavior list only -- it licenses no reads.
    1. Dispatch ONE tdd-cycle agent per behavior group in the wave, ALL in a single
       parallel message (do NOT set model -- the agent defines its own). Each prompt carries:
       - Task description (what behaviors to test -- may be a cohesive batch)
       - Relevant test file paths
       - When the wave has more than one group, the parallel-wave notice:
         "PARALLEL WAVE: other tdd-cycle agents are running concurrently on disjoint
         files. Do not read or modify files outside your behavior group's test files
         and implementation area. Skip your full-suite run (Phase 2, step 6) -- the
         orchestrator runs it once for the wave. Still report FULL_SUITE_COMMAND."
       The agent loads test-core (RED) and code-core (GREEN) in its own context; the
       orchestrator loads no hub or language skills and reads no target files.
    2. After ALL agents in the wave return, capture from each tdd-cycle output:
       TEST_FILE, TEST_NAME, TEST_COMMAND, FULL_SUITE_COMMAND, FAILURE_OUTPUT,
       IMPLEMENTATION_FILES, TEST_OUTPUT, STATUS, NOTES (optional)
       NOTES lines are out-of-lane observations (often another wave agent's mid-edit
       file): judge each against the wave's final state after verification -- most
       resolve themselves when the owning agent finishes -- and surface the rest to
       the user at task close, never silently dropped
       Then clear the guards the agents raised -- never mid-wave; a running agent
       still needs its markers:
       git_dir=$(git rev-parse --git-dir)
       rm -f "$git_dir/tdd-cycle-active" "$git_dir"/tdd-red-phase*
       (while tdd-cycle-active exists, a hook blocks all git add/commit -- including
       yours; the tdd-red-phase.<agent_id> files are per-agent read guards)
    3. Handle non-PASSED statuses, per agent:
       - PASSED_UNEXPECTEDLY -> behavior already exists; report to user;
         ask: skip (next behavior) or revise test scope?
       - STUCK + PHASE: RED -> test writing failed; report diagnostics to user
       - STUCK + PHASE: GREEN -> implementation failed; report diagnostics to user;
         ask: adjust test, try manually, or skip?
       - TEST_FLAWED -> report REASON + EVIDENCE to user;
         ask: fix test manually or revise scope?
       A non-PASSED cycle never blocks verifying the wave's PASSED cycles -- the
       wave was independent by construction. Verify the PASSED cycles first
       (step 4), then surface the non-PASSED ones.
    4. For each PASSED cycle:
       a. Inspect FAILURE_OUTPUT -- confirm it shows expected failure (feature missing, not typo)
       b. Run TEST_COMMAND yourself -- verify specific tests pass
       Then, ONCE for the whole wave:
       c. Run FULL_SUITE_COMMAND yourself -- verify full suite passes (no regressions)
       d. If verification fails -> report to user; exclude the affected cycle(s)
          from the COMMIT phase
       e. Do NOT commit -- no commit happens until the COMMIT phase, after REFACTOR.
          Retain each cycle's TEST_FILE(s) and IMPLEMENTATION_FILES for it.

  CONTINUE:
    5. More waves?
       - Executing a plan task -> the task's behavior list decides: continue until every
         group in the task is done. Never pause to ask the user mid-task -- the plan
         approval already answered "more behaviors?".
       - Ad hoc invocation -> ask user: more behaviors to implement? -> loop or exit

END LOOP

REFACTOR (once, after last cycle, BEFORE any commit -- never set model on any
dispatch in this sequence):
  10. Compute total insertions across this invocation's files: register new files
      from ALL_CHANGED_FILES with git add -N <paths>, then
      git diff --stat -- <ALL_CHANGED_FILES>
      (nothing is committed yet; scoping to ALL_CHANGED_FILES keeps unrelated
      uncommitted work out of the count)
  11. If < 50 insertions: log "REFACTOR skipped: <N> lines", go to COMMIT
  12. If >= 50 insertions:
      a. Split changed files into implementation files and test files; dispatch
         code-distiller on each set, in one parallel message
      b. After both return: dispatch subagent_type: vet-comments once over ALL
         changed files (distillation rewrites the code its comments describe);
         it is read-only and returns ### Finding N blocks
      c. Triage the findings -- no skill loads, no file reads:
         score 0 -> discard; score >= 75 -> fix queue; below 75 -> report to the
         user at task close, never silently dropped
      d. Fix queue non-empty -> group findings into transitive file groups
         (findings sharing any target file share a group); dispatch one
         code-mender per group in a single parallel message, passing per finding:
           Issue: <description>
           Location: <file:line>
           Severity: <high if the Impact tag ranks in the lens's top two, else medium>
           Suggested fix: <reasoning from the finding>
      e. Any edits applied -> re-run FULL_SUITE_COMMAND; when an enclosing workflow
         defines a per-task gate (e.g. a hardening round's gate block), run that gate
         instead -- it subsumes the suite re-run, and every commit must sit behind
         the full gate, never a subset
         - green -> go to COMMIT
         - red -> surface the failing output; do not commit

COMMIT (last phase -- refactor edits are already in the files, so every commit
contains the cleaned-up code; there is no separate refactor commit):
  13. When an enclosing workflow defines a pre-commit verification step (e.g. a
      plan task's Verify block dispatching claim-reviewer), run it NOW and resolve
      its findings -- verification always precedes the commit, never follows it.
  14. Approval gate -- the skill prescribes WHEN to commit; the user's approval
      authorizes THAT it happens. A PLAN TASK is a numbered task from a plan
      the user approved this session; everything else is AD HOC:
      - Plan task or autocommit active -> commit proceeds without pausing
        (approval already granted).
      - Ad hoc -> list each cycle's test files and implementation files in
        commit order. STOP -- no git commit in this turn. Wait for the user's
        next message with explicit approval. "Present and proceed" in a single
        turn is committing without approval.
      This gate is the TDD orchestrator's own rule, not delegated to
      write-commit. Loading write-commit does not absorb or replace it.
  15. Load Skill(write-commit), then commit cycle by cycle (the agents NEVER
      commit -- you own this), in TDD order:
      - stage that cycle's TEST_FILE(s) only -> commit (tests first)
      - stage that cycle's IMPLEMENTATION_FILES -> commit
      Commits are serial even when the waves were parallel -- never interleave
      two cycles' files in one commit. Cycles whose file sets overlap (dependent
      waves touching the same file) merge into one commit pair: their test files
      in one commit, their implementation files in the next.
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
[multi-group wave only] the PARALLEL WAVE notice from step 1
```

**tdd-cycle -> Orchestrator:**

The field-by-field contract (STATUS values, per-status field sets, examples) is owned by
`agents/tdd-cycle.md` § Output Format -- the single source of truth. Do not restate it here; if this
file and the agent file ever disagree, the agent file wins.

**Accumulated across all cycles (for REFACTOR and COMMIT):**

```text
ALL_CHANGED_FILES: <all files modified/added across all RED + GREEN cycles>
FULL_SUITE_COMMAND: <command from first RED output, retained by orchestrator>
Per cycle: TEST_FILE(s) + IMPLEMENTATION_FILES, retained for the COMMIT phase
```
