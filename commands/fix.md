---
name: fix
description: >
  Use when a bug, test failure, or regression needs both diagnosis and a fix.
  Use when root cause is unknown and you need end-to-end resolution.
argument-hint: "[bug description, error message, or failing test]"
---

# Fix

End-to-end bug fix pipeline: investigate root cause, then implement the fix with TDD.

## Process

**Do NOT investigate in the main context.** No running tests, no reading code, no forming hypotheses
here. Dispatch the agent immediately — it does all the work.

### Phase 1: Investigation

Immediately dispatch an opus agent (`model: opus`) to investigate the root cause. The agent loads
the investigate skill via `Skill(investigate)` and runs all three phases.

**Agent prompt must include:**

- The bug description or error from the user's argument
- Instruction to load the investigate skill via `Skill(investigate)`
- Instruction to return a structured root cause statement:
  - **Root cause:** what's wrong and where (`file:line`)
  - **Evidence:** what confirmed it
  - **Expected behavior:** what should happen instead

**Skip investigation if** the user already provides a confirmed root cause (not just a symptom).
Signs of a confirmed root cause: specific file and line reference, explanation of why it fails, not
just "it crashes" or "tests fail."

### Checkpoint: Verify root cause before proceeding

Read the agent's result. If it returned a confirmed root cause with evidence, proceed to Phase 2.

If the agent hit its circuit breaker or could not confirm a root cause, **stop and surface to the
user** — do not proceed to TDD without a diagnosis.

### Phase 2: Fix

Load the tdd skill via `Skill(tdd)` in the main context. Pass the confirmed root cause from Phase 1
as the behavior to test and fix. The TDD cycle takes it from there: failing test → implementation →
verify.

**Skip TDD if** the project has no test suite. In that case, implement the fix directly based on the
root cause and verify manually.
