---
name: tdd
description: >
  Use when implementing any feature, behavior change, or bug fix in a project with a test suite.
  Also use when asked to follow TDD or invoked via /tdd. Use when you think "I'll add tests later"
  — that's rationalization. Not for projects without a test suite.
argument-hint: "[feature or behavior to implement]"
---

# Test-Driven Development (TDD)

**Feature / Behavior:** $ARGUMENTS

## Table of Contents

- [Overview](#overview)
- [When to Use](#when-to-use)
- [Plans and TDD](#plans-and-tdd)
- [The Iron Law](#the-iron-law)
- [Architecture: Context-Isolated Subagents](#architecture-context-isolated-subagents)
- [Language Skill Dispatch](#language-skill-dispatch)
- [Batching: Cohesive vs. Unrelated](#batching-cohesive-vs-unrelated)
- [Parallel Waves: Independent Groups Run Concurrently](#parallel-waves-independent-groups-run-concurrently)
- [Orchestration Flow](#orchestration-flow)
- [Red-Green-Refactor](#red-green-refactor)
- [Circuit Breaker](#circuit-breaker)
- [Example: Bug Fix](#example-bug-fix)
- [Verification Checklist](#verification-checklist)
- [When Stuck](#when-stuck)
- [Debugging Integration](#debugging-integration)

## Overview

Write the test first. Watch it fail. Write minimal code to pass. Context-isolated via subagents.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## When to Use

**Always:**

- New features and behavior changes
- Bug fixes
- Refactoring with behavior implications

**Exceptions (ask your human partner):**

- Throwaway prototypes
- Generated code
- Configuration files

Thinking "skip TDD just this once"? Stop. That's rationalization.

## Plans and TDD

**Before creating any plan, load `Skill(write-plan)`.** Always. No exceptions.

When the project has a test suite, plans describe **behaviors to implement** plus the files they
touch (`write-plan`'s Files section) — never line numbers, inline code, or prescribed
implementations. Those details compromise the agents' context isolation; file paths do not (the
orchestrator hands `tdd-cycle` the test file paths anyway). Each plan task ends with **"Use `/tdd`
for implementation."** — no inline RED/GREEN steps, no test assertions, no implementation code.

When the project has no test suite, plans describe implementation directly (files, approach,
specific changes) — TDD constraints don't apply.

**Good:** "Modify `hud/prepare.lua`: accept hud.duration as a positive number, default 0.5. Use
`/tdd` for implementation." **Bad:** "Update prepare.lua:614, validate as positive number." —
prescribes implementation.

## The Iron Law

No production code without a failing test first. See `references/philosophy.md` for the full
principles, rationalizations table, and red flags checklist.

## Architecture: Context-Isolated Subagents

Context isolation prevents the LLM from designing tests around planned implementation.

| Phase     | Agent                                            | Can see (Phase 1 / Phase 2)                      | Cannot see/modify                          |
| --------- | ------------------------------------------------ | ------------------------------------------------ | ------------------------------------------ |
| RED-GREEN | `tdd-cycle`                                      | Phase 1: tests, stubs, public API / Phase 2: all | Phase 1: impl source / Phase 2: test files |
| REFACTOR  | distiller → vet-comments → mender (if ≥50 lines) | Everything                                       | N/A (see REFACTOR section)                 |

### Mandatory Entry Point

**NEVER dispatch `tdd-cycle` directly.** This skill is the orchestrator — without it, no phase
verification, no circuit breaker, no structured data passing.

### Dispatch First — No Prep Tool Calls

**Within each cycle, the `tdd-cycle` dispatch is the first tool call.** Between the task's behavior
list and the Agent call there is nothing to read, run, or check: no Read, no Bash, no Glob, no Grep.
Every "prep" step you can name belongs elsewhere — language detection (TSTL markers, framework
checks) is the agent's hub dispatch; a baseline suite run duplicates work the agent's RED phase
owns; your own TEST_COMMAND runs come after the agent returns (Verify GREEN). Announcing the
dispatch is not the dispatch — only the Agent call is. Each tool call inserted before it is a step
out of the router role into the implementer role, and that drift ends with the orchestrator writing
RED tests inline while still believing it is about to dispatch.

| Excuse                                            | Reality                                                                          |
| ------------------------------------------------- | -------------------------------------------------------------------------------- |
| "Checking TSTL markers is routing, not reading"   | You pass paths, never a language. tdd-cycle's hubs route in its own context.     |
| "A green baseline confirms the suite works first" | tdd-cycle resolves and runs the commands in RED. Your first run is Verify GREEN. |
| "I said I'd dispatch — these reads are just prep" | The announcement is not the dispatch. Any prep before the Agent call is drift.   |

## Language Skill Dispatch

The orchestrator loads no testing or coding skills. `tdd-cycle` loads `Skill(test-core)` in its RED
phase and `Skill(code-core)` in its GREEN phase, inside its own context; each hub dispatches the
matching language leaf and the leaf auto-loads domain overlays. The orchestrator loads a hub only in
the fallback case where it must edit files itself (e.g., a REFACTOR mender skipped a finding you
then fix by hand) — `rules/skill-loading.md` applies as usual at that point.

**The orchestrator routes; it never reads target files.** Dispatch prompts carry behavior
descriptions and file paths; every agent reads its own files in its own fresh context. The only
contents the orchestrator loads are agent reports and the output of TEST_COMMAND /
FULL_SUITE_COMMAND. Reading a test or implementation file "to understand the API", "to batch
better", "to detect the language", or "before dispatching" is context stolen from the steps only the
orchestrator can do — verification, triage, commits. Batching is decided from the plan's behavior
list, never from file contents. If the extension has no dispatch row in `rules/skill-loading.md`,
the agent notes "no matching skill" and proceeds on hub principles alone.

`tdd-cycle` resolves TEST_COMMAND and FULL_SUITE_COMMAND during its RED phase — the orchestrator
uses these for independent GREEN verification.

## Batching: Cohesive vs. Unrelated

Each RED-GREEN cycle covers a **behavior group** — one behavior or a batch of related behaviors that
share the same implementation area. Isolation is a property of the **dispatch**, not the behavior:
one RED that writes tests for three behaviors landing in the same module loses nothing, and every
dispatch re-pays the agent's fixed startup cost (context, skill loads, file reads) — under-batching
is the expensive failure.

**Batch together** (single RED-GREEN cycle):

- Behaviors whose implementations land in the same module or file set — even when their tests fail
  for different structural reasons
- Edge cases and variants of the same behavior (empty input, whitespace, format variants)
- Validation rules for the same field or data type

**Keep separate** (distinct RED-GREEN cycles):

- Behaviors touching different modules or subsystems
- Anything where a single GREEN implementation would be too large to reason about or verify as one
  diff

**Rule of thumb:** group by where the implementation lands, not by why the tests fail. "Different
failure modes" or "could ship independently" are never reasons to split behaviors that live in the
same files.

## Parallel Waves: Independent Groups Run Concurrently

Batching decides what shares a cycle; **waves decide which cycles run at the same time.** Behavior
groups that are independent — neither consumes anything the other introduces (no new function, type,
or module from one used by the other) and their test files and implementation areas are disjoint —
form one wave: one `tdd-cycle` per group, all dispatched in a **single parallel message**. A group
that consumes another group's output runs in a later wave, after the producer's cycle is verified —
its code is on disk; commits wait until after REFACTOR.

Independence is judged from the plan's behavior list alone — never by reading files (the same rule
that governs batching). Unsure → serialize; a wasted wave costs one dispatch round, while two agents
editing the same file costs a corrupted cycle.

Wave mechanics (full loop in `references/orchestration-flow.md`):

- Multi-group wave prompts carry the PARALLEL WAVE notice: each agent stays inside its group's files
  and skips its own full-suite run.
- Verification: each cycle's TEST_COMMAND, then FULL_SUITE_COMMAND **once per wave**.
- No commits mid-loop: commits stay serial and per-cycle, in TDD order, but happen only in the
  COMMIT phase after REFACTOR — never interleave two cycles' files in one commit.
- Guards (`tdd-cycle-active`, per-agent `tdd-red-phase.<agent_id>` read markers) are cleared only
  after every agent in the wave has returned.
- One STUCK or TEST_FLAWED cycle never blocks the wave's PASSED cycles — verify those first, then
  surface the failure; the PASSED cycles commit with the rest after REFACTOR.

Serializing independent groups wastes wall-clock time the same way splitting cohesive behaviors
wastes dispatches; parallelizing dependent ones hands an agent a GREEN phase whose prerequisite code
doesn't exist yet. Both are wave-planning failures.

## Orchestration Flow

For the detailed entry-point logic, RED-GREEN-REFACTOR loop pseudocode, and phase data contracts,
see `references/orchestration-flow.md`.

## Red-Green-Refactor

### RED — Write Failing Tests

The `tdd-cycle` agent's RED phase writes tests for one behavior group — a single behavior or a
cohesive batch (see Batching section above). Each individual test still covers one thing.

**Good** — Three tests, one RED-GREEN cycle (all fail because CatalogEntry doesn't exist yet):

```python
# Cohesive batch: all test CatalogEntry validation (same model, same implementation area)
def test_catalog_entry_parses_valid_section():
    entry = CatalogEntry(**valid_catalog)
    assert entry.name == "My App"

def test_catalog_entry_rejects_missing_field():
    with pytest.raises(ValidationError):
        CatalogEntry(**{k: v for k, v in valid_catalog.items() if k != "name"})

def test_catalog_entry_rejects_invalid_type():
    with pytest.raises(ValidationError):
        CatalogEntry(**{**valid_catalog, "type": "invalid"})
```

**Bad** — Same model, same implementation area — splitting wastes dispatches without improving
isolation:

```python
# One test per RED-GREEN cycle for the same model — 3 agent dispatches for no benefit
# Cycle 1: RED → GREEN for test_catalog_entry_parses_valid_section
# Cycle 2: RED → GREEN for test_catalog_entry_rejects_missing_field
# Cycle 3: RED → GREEN for test_catalog_entry_rejects_invalid_type
```

**Requirements:**

- One behavior group per cycle (see Batching section)
- Each individual test covers one thing — clear name describing behavior
- Real code (no mocks unless unavoidable)

### Verify RED — Inspect FAILURE_OUTPUT

**MANDATORY. Never skip.** The agent runs both phases internally, so you cannot re-run the failing
state. `FAILURE_OUTPUT` is the evidence that substitutes for it: the failure message must be
expected, and it must fail because the feature is missing (not typos).

The agent NEVER commits — and neither do you until the COMMIT phase after REFACTOR, in TDD order
(test files first, then implementation files; see the orchestration flow). Never ask the agent for a
commit or instruct it to make one.

**`STATUS: PASSED_UNEXPECTEDLY`?** Behavior already exists. Report to user and ask: skip or revise
scope?

**`STATUS: STUCK + PHASE: RED`?** Test writing failed. Report diagnostics to user.

### GREEN — Minimal Code

The `tdd-cycle` agent's GREEN phase writes simplest code to pass the test.

**Good** — Just enough to pass:

```typescript
async function retryOperation<T>(fn: () => Promise<T>): Promise<T> {
  for (let i = 0; i < 3; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i === 2) throw e;
    }
  }
  throw new Error('unreachable');
}
```

**Bad** — Over-engineered:

```typescript
async function retryOperation<T>(
  fn: () => Promise<T>,
  options?: {
    maxRetries?: number;
    backoff?: 'linear' | 'exponential';
    onRetry?: (attempt: number) => void;
  }
): Promise<T> {
  // YAGNI
}
```

Don't add features, refactor other code, or "improve" beyond the test.

### Verify GREEN — Watch It Pass

**MANDATORY. Run TEST_COMMAND and FULL_SUITE_COMMAND yourself** — do not rely solely on tdd-cycle's
report. In a multi-group wave, run each cycle's TEST_COMMAND, then FULL_SUITE_COMMAND once for the
wave (the agents skipped it by instruction).

Confirm:

- Specific test passes
- Full test suite passes
- Output pristine (no errors, warnings)

**Test fails?** Fix code, not test.

**Other tests fail?** Fix regressions now.

### REFACTOR — Clean Up (after the last cycle, before any commit)

REFACTOR runs **once** after all RED-GREEN cycles complete, not per-cycle — and **before any
commit**. Nothing is committed until REFACTOR finishes, so every commit contains the cleaned-up
code; there is no separate refactor commit.

Compute total insertions across all files modified/added during this `/tdd` invocation: register new
files with `git add -N`, then run `git diff --stat -- <ALL_CHANGED_FILES>`. Scoping the diff to the
invocation's files keeps unrelated uncommitted work out of the count. If total insertions are **< 50
lines**, skip REFACTOR and go straight to Commit.

If **≥ 50 lines**, run the distill-and-mend sequence. The orchestrator dispatches and triages; it
never loads hub skills and never edits files here:

1. Split changed files into impl and test files. Dispatch `code-distiller` on the impl files and
   `code-distiller` on the test files, in one parallel message. Do NOT set model on any dispatch in
   this sequence — each agent defines its own, and each loads its skills in its own context, so pass
   no skill in the prompt.
2. After both return, dispatch `subagent_type: vet-comments` once over **all** changed files —
   distillation rewrites the code its comments describe, so the comment pass runs after the shape
   settles. It is read-only and returns `### Finding N` blocks.
3. Triage the findings — no skill loads, no file reads: score 0 → discard (declared false positive);
   score ≥ 75 → fix queue; below 75 → report to the user at task close, never silently dropped.
4. Non-empty fix queue → group findings into transitive file groups (findings sharing any target
   file share a group) and dispatch one `code-mender` per group in a single parallel message — never
   one per finding; concurrent menders sharing a file race each other. Pass per finding: Issue /
   Location / Severity (high for the top two ranks of the lens's Impact enum, else medium) /
   Suggested fix.
5. If any agent applied edits, re-run FULL_SUITE_COMMAND — or, when an enclosing workflow defines a
   per-task gate (e.g. a hardening round's gate block), run that gate instead; it subsumes the suite
   re-run. Green → proceed to Commit. Red → surface the failing output; do not commit.

The heavier review lenses (`vet-code`, `vet-test`, `bug-scanner`) are deliberately absent: they run
in the pre-push `/preflight` pass, which owns snapshots, gates, and fix verification. REFACTOR's job
is shape and comment hygiene on freshly written code, so later tasks don't inherit — and imitate —
crust.

### Commit — Last Phase

Commits come after REFACTOR, never before or during the loop. When an enclosing workflow defines a
pre-commit verification step (e.g. a plan task's **Verify** block dispatching `claim-reviewer`), run
it now and resolve its findings first — verification always precedes the commit. Then load
`Skill(write-commit)` and commit cycle by cycle in TDD order (that cycle's test files first, then
its implementation files; staging rules in `references/orchestration-flow.md`).

### Repeat

Next wave. One vertical slice (or cohesive batch) per cycle; independent cycles share a wave.

## Circuit Breaker

### Tier 1: After 3 failed GREEN attempts

The `tdd-cycle` agent's GREEN phase switches to a fundamentally different approach (different
algorithm, alternative API, restructured logic).

### Tier 2: After 5 total GREEN failures

Agent reports STUCK with diagnostics. Orchestrator presents to user with options:

- Adjust the test (maybe it's too strict)
- Try manual implementation
- Skip this behavior for now

## Example: Bug Fix

**Bug:** Empty email accepted

**RED** (via tdd-cycle agent, RED phase)

```typescript
test('rejects empty email', async () => {
  const result = await submitForm({ email: '' });
  expect(result.error).toBe('Email required');
});
```

### Verify RED

```text
FAIL: expected 'Email required', got undefined
```

**GREEN** (via tdd-cycle agent, GREEN phase)

```typescript
function submitForm(data: FormData) {
  if (!data.email?.trim()) {
    return { error: 'Email required' };
  }
  // ...
}
```

### Verify GREEN

```text
PASS
```

**REFACTOR** — Run the distill-and-mend sequence if ≥50 lines changed. Extract validation for
multiple fields if needed. Only then commit.

## Verification Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing (confirmed via FAILURE_OUTPUT from tdd-cycle)
- [ ] Each test failed for expected reason (feature missing, not typo)
- [ ] Committed each cycle yourself in TDD order (tests first, then implementation), only after
      REFACTOR finished — the agent never commits
- [ ] Wrote minimal code to pass each test (via tdd-cycle agent)
- [ ] All tests pass
- [ ] Output pristine (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Showed test output proving pass (not "should pass" — actual output)
- [ ] Edge cases and errors covered
- [ ] REFACTOR ran (if ≥50 lines changed) or skipped with reason logged — before any commit

Can't check all boxes? You skipped TDD. Start over.

## When Stuck

| Problem                        | Solution                                                             |
| ------------------------------ | -------------------------------------------------------------------- |
| Don't know how to test         | Write wished-for API. Write assertion first. Ask your human partner. |
| Test too complicated           | Design too complicated. Simplify interface.                          |
| Must mock everything           | Code too coupled. Use dependency injection.                          |
| Test setup huge                | Extract helpers. Still complex? Simplify design.                     |
| tdd-cycle can't find API       | Add type stubs or update `__init__.py` exports.                      |
| tdd-cycle hits circuit breaker | Review test assumptions. Consider adjusting test scope.              |

## Debugging Integration

Bug discovered mid-session? Write a failing test via tdd-cycle before fixing. For standalone bug
reports (unknown root cause), use `/fix` first — it investigates, then drives TDD.

## Pressure Testing

RED phase failures this skill was designed to address:

- Agents writing implementation first, then retrofitting tests
- Batching unrelated behaviors into one RED-GREEN cycle to "save time"
- Splitting same-module behaviors into per-behavior cycles because they "fail differently" — paying
  an extra dispatch for zero isolation gain
- Orchestrators reading source files during Phase 1 to "understand the API"
- Orchestrators pre-reading test files "to batch better" or "to write a better dispatch prompt"
- Orchestrators inserting "prep" tool calls after announcing a dispatch — a language-marker read, a
  baseline suite run — then sliding into inline RED as the implementer role takes over
- Agents dispatching tdd-cycle directly, bypassing the orchestrator
- Orchestrators serializing independent behavior groups one dispatch at a time — or reading files
  "to check independence" before planning a wave
- Orchestrators putting a consumer group in the same wave as its producer because "the agent can
  stub it"

See `references/philosophy.md` for the full rationalization table and red flags.
