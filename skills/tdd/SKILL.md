---
name: tdd
description: >
  Use when implementing any feature, behavior change, or bug fix in a project with a test suite.
  Also use when asked to follow TDD or invoked via /tdd.
---

# Test-Driven Development (TDD)

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

Plans describe **behaviors to implement**, not inline RED/GREEN steps. Never inline test assertions
or implementation code in plan tasks.

A plan that contains both test assertions and implementation code defeats context isolation — the
RED agent should write tests without seeing implementation plans, and the GREEN agent should write
code guided only by failing tests. When the plan inlines both, that isolation is broken.

**Good:** "Behaviors: (1) resolve by name (2) resolve by type. Use `/tdd` for implementation."

**Bad:** "RED: assert X created. GREEN: fix lookup to use Y." — prescribes test + impl in one place.

## The Iron Law

```text
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over.

**No exceptions:**

- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Don't look at it
- Delete means delete

Implement fresh from tests. Period.

## Architecture: Context-Isolated Subagents

TDD in a single context window is compromised — the LLM designs tests around the implementation it's
already planning. This skill enforces context isolation by dispatching separate agents for RED and
GREEN phases. Each agent sees only what it needs.

| Phase    | Agent        | Can see                       | Cannot see/modify                           |
| -------- | ------------ | ----------------------------- | ------------------------------------------- |
| RED      | `tdd-red`    | Tests, type stubs, public API | Implementation source                       |
| GREEN    | `tdd-green`  | Everything                    | Cannot modify test files                    |
| REFACTOR | `/preflight` | Everything                    | N/A (runs code-distill, vet-code, vet-test) |

### Mandatory Entry Point

**NEVER dispatch `tdd-red` or `tdd-green` agents directly.** This skill is the orchestrator.
Dispatching agents without this skill means no orchestration flow, no phase verification, no circuit
breaker, and no structured data passing between phases.

Thinking "I know the pattern, I'll just dispatch agents myself"? That's rationalization. Invoke
`/tdd` first.

## Language Detection

Detect from file extensions and config files:

| Signal           | Language   | Test runner      |
| ---------------- | ---------- | ---------------- |
| `pyproject.toml` | Python     | `uv run pytest`  |
| `package.json`   | TypeScript | `npx vitest run` |
| `*.rockspec`     | Lua        | `busted`         |

## Batching: Cohesive vs. Unrelated

Each RED-GREEN cycle covers a **behavior group** — one behavior or a cohesive batch of related
behaviors that share the same implementation area.

**Batch together** (single RED-GREEN cycle):

- Edge cases of the same behavior (empty input, whitespace, too-long, special chars)
- Closely related micro-features that touch the same function/module
- Validation rules for the same field or data type
- Format variants of the same operation (CSV, JSON, YAML output)

**Keep separate** (distinct RED-GREEN cycles):

- Behaviors touching different modules or subsystems
- Features that could ship independently
- Behaviors with different failure modes or error paths
- Anything where a single GREEN implementation would be too large to reason about

**Rule of thumb:** If all the tests will fail for the same structural reason (missing function,
missing branch, missing parameter), they belong in one batch. If they'd fail for different reasons,
they're separate cycles.

## Orchestration Flow

```text
LOOP (one behavior group per cycle):

  RED:
    1. Dispatch tdd-red agent with:
       - Task description (what behaviors to test — may be a cohesive batch)
       - Language and test runner
       - Relevant test file paths
    2. Capture: test file, test name(s), failure output
    3. Verify all tests actually failed
    4. If any test PASSED_UNEXPECTEDLY:
       → Report to user: behavior already exists
       → Ask: skip (next behavior) or revise test scope?

  GREEN:
    5. Dispatch tdd-green agent with:
       - Test file path
       - Test name(s)
       - Failure output
       - Test command
    6. Capture: implementation files, test results
    7. Verify: all new tests pass + full suite passes
    8. If STUCK (5 failures):
       → Report diagnostics to user
       → Ask: adjust test, try manually, or skip?

  REFACTOR:
    9.  Split CHANGED_FILES into implementation files and test files
    10. Dispatch two agents in parallel (single message, two Agent tool calls):
        - Agent A: code-distill → vet-code (→ vet-code again if changes) on impl files
        - Agent B: code-distill → vet-test (→ vet-test again if changes) on test files
    11. If any fixes applied, re-run test suite to confirm tests still green

  CONTINUE:
    12. Ask user: more behaviors to implement? → loop or exit
```

### What Passes Between Phases

Only structured data — never reasoning or analysis:

**RED → GREEN:**

```text
TEST_FILE: <path>
TEST_NAME: <name(s)>
TEST_COMMAND: <command>
FAILURE_OUTPUT: <output>
```

**GREEN → REFACTOR:**

```text
CHANGED_FILES: <list of all files modified in RED + GREEN>
```

## Red-Green-Refactor

### RED — Write Failing Tests

The `tdd-red` agent writes tests for one behavior group — a single behavior or a cohesive batch (see
Batching section above). Each individual test still covers one thing.

**Good** — Three tests, one RED-GREEN cycle (all fail because CatalogEntry doesn't exist yet):

```python
# Cohesive batch: all test CatalogEntry validation (same model, same structural reason)
def test_catalog_entry_parses_valid_section():
    entry = CatalogEntry(**valid_catalog)
    assert entry.name == "My App"

def test_catalog_entry_rejects_missing_field(): with pytest.raises(ValidationError):
CatalogEntry(**{k: v for k, v in valid_catalog.items() if k != "name"})

def test_catalog_entry_rejects_invalid_type(): with pytest.raises(ValidationError):
CatalogEntry(**{**valid_catalog, "type": "invalid"})
```

**Bad** — Same model, same failure reason — splitting wastes time without improving isolation:

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

### Verify RED — Watch It Fail

**MANDATORY. Never skip.**

Confirm:

- Test fails (not errors)
- Failure message is expected
- Fails because feature missing (not typos)

**Test passes?** Behavior already exists. Report to user.

**Test errors?** Fix error, re-run until it fails correctly.

### GREEN — Minimal Code

The `tdd-green` agent writes simplest code to pass the test.

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

**MANDATORY.**

Confirm:

- Specific test passes
- Full test suite passes
- Output pristine (no errors, warnings)

**Test fails?** Fix code, not test.

**Other tests fail?** Fix regressions now.

### REFACTOR — Clean Up

Split changed files into implementation files and test files. Dispatch two agents in parallel
(single message, two Agent tool calls):

- **Agent A (impl):** general-purpose agent. "Simplify then review these implementation files:
  [list]. First apply code-distill (reduce complexity, DRY, naming, dead code). Then invoke
  `/vet-code` on the same files. If vet-code made changes, run `/vet-code` once more (max 2
  passes)."
- **Agent B (tests):** general-purpose agent. "Simplify then review these test files: [list]. First
  apply code-distill (reduce complexity, DRY, naming, dead code). Then invoke `/vet-test` on the
  same files. If vet-test made changes, run `/vet-test` once more (max 2 passes)."

Each agent runs distill → vet → (if changes) vet again, sequentially in its own context. The vet
benefits from seeing what was simplified, and a second pass catches improvements created by the
first. After both complete, re-run the test suite if either agent made changes.

Keep tests green. Don't add behavior.

For full review (bug scanning, compliance), run `/preflight` before committing.

### Repeat

Next behavior group. One vertical slice (or cohesive batch) per cycle.

## Circuit Breaker

### Tier 1: After 3 failed GREEN attempts

The `tdd-green` agent switches to a fundamentally different approach (different algorithm,
alternative API, restructured logic).

### Tier 2: After 5 total GREEN failures

Agent reports STUCK with diagnostics. Orchestrator presents to user with options:

- Adjust the test (maybe it's too strict)
- Try manual implementation
- Skip this behavior for now

## Good Tests

| Quality          | Good                                | Bad                                                 |
| ---------------- | ----------------------------------- | --------------------------------------------------- |
| **Minimal**      | One thing. "and" in name? Split it. | `test('validates email and domain and whitespace')` |
| **Clear**        | Name describes behavior             | `test('test1')`                                     |
| **Shows intent** | Demonstrates desired API            | Obscures what code should do                        |

## Why Order Matters

### "I'll write tests after to verify it works"

Tests written after code pass immediately. Passing immediately proves nothing:

- Might test wrong thing
- Might test implementation, not behavior
- Might miss edge cases you forgot
- You never saw it catch the bug

Test-first forces you to see the test fail, proving it actually tests something.

### "I already manually tested all the edge cases"

Manual testing is ad-hoc. No record, can't re-run, easy to forget cases.

### "Deleting X hours of work is wasteful"

Sunk cost fallacy. Working code without real tests is technical debt.

### "TDD is dogmatic, being pragmatic means adapting"

TDD IS pragmatic: finds bugs before commit, prevents regressions, documents behavior, enables
refactoring. "Pragmatic" shortcuts = debugging in production = slower.

### "Tests after achieve the same goals — it's spirit not ritual"

No. Tests-after answer "What does this do?" Tests-first answer "What should this do?" Tests-after
are biased by your implementation. 30 minutes of tests after is not TDD.

## Common Rationalizations

| Excuse                                  | Reality                                                                                          |
| --------------------------------------- | ------------------------------------------------------------------------------------------------ |
| "Too simple to test"                    | Simple code breaks. Test takes 30 seconds.                                                       |
| "I'll test after"                       | Tests passing immediately prove nothing.                                                         |
| "Tests after achieve same goals"        | Tests-after = "what does this do?" Tests-first = "what should this do?"                          |
| "Already manually tested"               | Ad-hoc, no record, can't re-run.                                                                 |
| "Deleting X hours is wasteful"          | Sunk cost fallacy. Keeping unverified code is technical debt.                                    |
| "Keep as reference, write tests first"  | You'll adapt it. That's testing after. Delete means delete.                                      |
| "Need to explore first"                 | Fine. Throw away exploration, start with TDD.                                                    |
| "Test hard = design unclear"            | Listen to test. Hard to test = hard to use.                                                      |
| "TDD will slow me down"                 | TDD faster than debugging. Pragmatic = test-first.                                               |
| "This is a new feature, not a bug fix"  | TDD applies to features too.                                                                     |
| "I need to see the whole picture first" | That's exploration. Delete it, start with TDD.                                                   |
| "Existing code has no tests"            | You're improving it. Add tests for existing code.                                                |
| "I can orchestrate the agents myself"   | The skill IS the orchestrator. Invoke `/tdd`.                                                    |
| "The plan already has RED/GREEN steps"  | Plans describe behaviors, not test/impl details. Use `/tdd`.                                     |
| "The plan template shows inline code"   | Plan templates with inline test/impl code don't apply to TDD. Describe behaviors + "Use `/tdd`". |
| "I already know RED-GREEN-REFACTOR"     | Knowing the pattern ≠ following the discipline. Invoke the skill.                                |
| "Each test needs its own cycle"         | Cohesive tests (same function, same failure reason) batch together. Don't waste cycles.          |
| "I'll batch these unrelated tests"      | Different modules/failure reasons = separate cycles. Batching ≠ dumping everything together.     |

## Red Flags — STOP and Start Over

- Code before test
- Test after implementation
- Test passes immediately
- Can't explain why test failed
- Tests added "later"
- Rationalizing "just this once"
- "I already manually tested it"
- "Tests after achieve the same purpose"
- "It's about spirit not ritual"
- "Keep as reference" or "adapt existing code"
- "Already spent X hours, deleting is wasteful"
- "TDD is dogmatic, I'm being pragmatic"
- "This is different because..."
- Dispatching `tdd-red`/`tdd-green` without invoking `/tdd` first
- Plan with inline RED/GREEN steps (test assertions + implementation code)
- Following a plan template that inlines test assertions and implementation code

**All of these mean: Delete code. Start over with TDD.**

## Example: Bug Fix

**Bug:** Empty email accepted

**RED** (via tdd-red agent)

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

**GREEN** (via tdd-green agent)

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

**REFACTOR** — Run /preflight. Extract validation for multiple fields if needed.

## Verification Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing (via tdd-red agent)
- [ ] Each test failed for expected reason (feature missing, not typo)
- [ ] Wrote minimal code to pass each test (via tdd-green agent)
- [ ] All tests pass
- [ ] Output pristine (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Edge cases and errors covered
- [ ] /preflight passed on all changed files

Can't check all boxes? You skipped TDD. Start over.

## When Stuck

| Problem                        | Solution                                                             |
| ------------------------------ | -------------------------------------------------------------------- |
| Don't know how to test         | Write wished-for API. Write assertion first. Ask your human partner. |
| Test too complicated           | Design too complicated. Simplify interface.                          |
| Must mock everything           | Code too coupled. Use dependency injection.                          |
| Test setup huge                | Extract helpers. Still complex? Simplify design.                     |
| tdd-red can't find API         | Add type stubs or update `__init__.py` exports.                      |
| tdd-green hits circuit breaker | Review test assumptions. Consider adjusting test scope.              |

## Debugging Integration

Bug found? Write failing test reproducing it via tdd-red. Follow TDD cycle. Test proves fix and
prevents regression.

Never fix bugs without a test.

## Testing Anti-Patterns

When adding mocks or test utilities, read @references/testing-anti-patterns.md to avoid common
pitfalls:

- Testing mock behavior instead of real behavior
- Adding test-only methods to production classes
- Mocking without understanding dependencies

## Final Rule

```text
Production code → test exists and failed first (via tdd-red)
Implementation → minimal pass (via tdd-green)
Cleanup → /preflight
Otherwise → not TDD
```

No exceptions without your human partner's permission.
