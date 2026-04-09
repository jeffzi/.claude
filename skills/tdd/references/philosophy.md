# TDD Philosophy

**Load this reference when:** context suggests resistance, rationalization, or uncertainty about TDD
principles.

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

## Good Tests

| Quality          | Good                                | Bad                                                 |
| ---------------- | ----------------------------------- | --------------------------------------------------- |
| **Minimal**      | One thing. "and" in name? Split it. | `test('validates email and domain and whitespace')` |
| **Clear**        | Name describes behavior             | `test('test1')`                                     |
| **Shows intent** | Demonstrates desired API            | Obscures what code should do                        |

## Common Rationalizations

| Excuse                                                                            | Reality                                                                              |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| "Too simple to test"                                                              | Simple code breaks. Test takes 30 seconds.                                           |
| "I'll test after" / "Tests after achieve same goals" / "Already manually tested"  | Tests-first = "what should this do?" Tests-after = "what does this do?" No record.   |
| "Deleting X hours is wasteful" / "Keep as reference, write tests first"           | Sunk cost. You'll adapt reference code -- that's testing after. Delete means delete. |
| "Need to explore first" / "I need to see the whole picture first"                 | Exploration is fine. Throw it away, then start with TDD.                             |
| "Test hard = design unclear"                                                      | Listen to test. Hard to test = hard to use.                                          |
| "TDD will slow me down" / "This is a new feature, not a bug fix"                  | TDD faster than debugging. Applies to features and fixes alike.                      |
| "Existing code has no tests"                                                      | You're improving it. Add tests for what you touch.                                   |
| "I can orchestrate the agents myself" / "I already know RED-GREEN-REFACTOR"       | Knowing != following. The skill IS the orchestrator. Invoke `/tdd`.                  |
| "Plan already has RED/GREEN steps" / "Plan template shows inline code"            | Plans describe behaviors, not test/impl details. Use `/tdd`.                         |
| "Each test needs its own cycle" / "I'll batch these unrelated tests"              | Cohesive tests (same failure reason) batch. Different modules = separate cycles.     |
| "Let me read the source first" / "I'll write the test inline, faster"             | RED agent reads what it needs. Context isolation exists for a reason.                |
| "Just one quick cycle, no plan needed" / "Plan needs impl details so agents know" | Multi-behavior tasks need a plan. Plans describe behaviors; agents figure out how.   |

## Red Flags -- STOP and Start Over

Any verbal rationalization from the table above, plus these architectural violations:

- Code before test / test passes immediately / can't explain why test failed
- Dispatching `tdd-cycle` without invoking `/tdd` first
- Orchestrator reading implementation source or writing test code directly
- Dispatching agents without a plan for multi-behavior tasks
- Dispatching agents from plan mode instead of writing plan tasks
- Plan with implementation details or inline RED/GREEN test/impl code

**All of these mean: Delete code. Start over with TDD.**
