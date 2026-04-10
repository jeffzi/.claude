# TDD Philosophy

**Load this reference when:** context suggests resistance, rationalization, or uncertainty about TDD
orchestration — specifically the Iron Law, the orchestrator-agent split, or when to dispatch
`tdd-cycle`.

**Also apply:** `Skill(test-core)` for cross-language testing principles (AAA, behavior vs.
implementation, parametrization, mocking anti-patterns). This reference is **TDD-orchestration
only**.

## The Iron Law

```text
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before test? Delete it. Don't keep it as "reference." Don't "adapt" it while writing
tests. Don't commit and "fix forward." Delete and start over with a failing test first.

**Violating the letter of the rules is violating the spirit of the rules.**

## TDD-Specific Rationalizations

| Excuse                                                        | Reality                                                                                  |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| "I'll orchestrate RED-GREEN-REFACTOR myself"                  | Context isolation is the entire point. Invoke `/tdd`.                                    |
| "Plan already has RED/GREEN steps" / "Plan shows inline code" | Plans describe behaviors, not test/impl details. Use `/tdd` for implementation.          |
| "Each test needs its own cycle" / "I'll batch later"          | Cohesive batches belong in one cycle. Different modules = separate cycles. See Batching. |
| "Let me read the source first" / "I'll write test inline"     | RED agent reads what it needs. Context isolation exists for a reason.                    |
| "Just one quick cycle, no plan needed"                        | Multi-behavior tasks need a plan. Plans describe behaviors; agents figure out how.       |
| "I'll dispatch `tdd-cycle` directly, skip the orchestrator"   | No phase verification, no circuit breaker, no data contracts. Always go through `/tdd`.  |

## Red Flags — STOP and Start Over

Architectural violations specific to TDD orchestration:

- Code before test / test passes immediately / can't explain why test failed
- Dispatching `tdd-cycle` without invoking `/tdd` first
- Orchestrator reading implementation source or writing test code directly
- Dispatching agents without a plan for multi-behavior tasks
- Dispatching agents from plan mode instead of writing plan tasks
- Plan contains implementation details or inline RED/GREEN test/impl code

**All of these: delete the code, start over with TDD.**
