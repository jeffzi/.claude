---
name: debug
description: >
  Use when encountering any bug, test failure, crash, error, regression, or unexpected behavior,
  before proposing fixes. Also use when a fix attempt fails twice — stop guessing and start
  investigating. Use when you see a stack trace and don't understand the root cause.
---

# Systematic Debugging

**Violating the letter of the rules is violating the spirit of the rules.**

## When NOT to Use

- Root cause is already known and you have a failing test — go straight to `/tdd`
- GSD project debugging with persistent state — use `/gsd:debug` instead
- Configuration or environment issues — just fix the config

## The Iron Law

**No fixes without root cause investigation first.**

If you're about to change code because "it might fix it" — stop. That's guessing, not debugging.
Guessing leads to: wrong fix, new bugs, wasted cycles, masked root cause.

## Four Phases

### Phase 1: Root Cause Investigation

Gather evidence before forming any hypothesis.

1. **Read the error** — full stack trace, exact message, line numbers. Not a summary.
2. **Reproduce** — run the failing command yourself. If you can't reproduce, you can't verify a fix.
3. **Check recent changes** — `git log --oneline -10`, `git diff`. Did something just change?
4. **Trace data flow** — follow the actual values through the code path. Read the code, don't
   assume.
   - **Multi-component systems:** When the bug crosses service/process boundaries, log what enters
     and exits each component boundary. Run once to find WHERE it breaks, then analyze.
5. **Check assumptions** — types, nullability, initialization order, environment differences.

**Output:** A specific, falsifiable statement of what's wrong and where. "The error occurs because X
is Y when it should be Z, at `file:line`."

### Phase 2: Pattern Analysis

Compare what works with what doesn't.

1. **Find a working case** — same code path that succeeds. What's different?
2. **Isolate the variable** — what single difference causes the failure?
3. **Check boundaries** — does it fail at specific values, sizes, timing, or ordering?
4. **Check dependencies** — what config, environment, or component state does the failing path
   assume?

**Output:** The specific difference between working and failing cases. "It works when X but fails
when Y, because Z differs."

### Phase 3: Hypothesis Testing

One hypothesis at a time. Minimal test. Verify.

1. **State the hypothesis** — "If X is the cause, then changing Y should produce Z."
2. **Design the smallest test** — one variable, one change.
3. **Run it** — observe. Did it confirm or refute?
4. **If refuted** — back to Phase 1 with new evidence. Don't stack hypotheses.

**Output:** A confirmed hypothesis with evidence. "Confirmed: X causes Y. Evidence: changing X to Z
resolves the failure."

### Phase 4: Implementation

Now — and only now — fix it.

1. **Write a failing test** that reproduces the bug (hand off to `/tdd` for the fix).
2. **Single fix** — address the root cause. Don't fix "related" things.
3. **Verify** — the test passes, no regressions, full suite green.

## Red Flags — Catch Yourself

| You're thinking...                    | What to do instead                                        |
| ------------------------------------- | --------------------------------------------------------- |
| "Let me just try this quick change"   | State your hypothesis first. Then test it.                |
| "I think it might be..."              | "Might" means you don't know. Gather more evidence.       |
| "This worked in a similar case"       | Similar is not identical. Verify this specific case.      |
| "Let me fix this and see if it helps" | That's guessing. Reproduce first, then diagnose.          |
| "The error message is misleading"     | Maybe. But verify before dismissing it.                   |
| "It's probably a race condition"      | Prove it. Add logging, reproduce under controlled timing. |

## Rationalization Prevention

| Excuse                                 | Reality                                                      |
| -------------------------------------- | ------------------------------------------------------------ |
| "I already know what's wrong"          | If you did, you wouldn't need to debug. Verify.              |
| "The fix is obvious"                   | Obvious fixes that skip diagnosis often mask the real issue. |
| "I'll investigate after I fix it"      | You won't. The urgency disappears once it "works."           |
| "This is taking too long, just fix it" | Guessing takes longer. Systematic diagnosis is faster.       |
| "It's definitely this one thing"       | "Definitely" without evidence is a guess.                    |

## Circuit Breaker

**3+ failed fix attempts:** Stop fixing. You're treating symptoms, not the disease.

- Question your mental model of the code
- Re-read the error from scratch (fresh eyes)
- Check if the bug is in a different layer than you think
- If each fix reveals a new problem in a different place, the issue may be architectural — not a
  bug. Surface this distinction to the user.
- Surface to the user: "I've attempted N fixes without success. Here's what I've tried and what I've
  ruled out. I think the issue may be in [area] — want me to investigate there, or do you have
  context that might help?"

## When Investigation Finds No Root Cause

If you've completed all phases and genuinely cannot identify the root cause:

1. Document what you investigated and ruled out.
2. Implement appropriate handling (retry, timeout, error message) as a pragmatic response.
3. Add monitoring or logging to capture the next occurrence.

**But:** 95% of "no root cause" conclusions come from incomplete investigation. Before reaching this
point, verify you've traced the full data flow, checked all component boundaries, and reproduced
under controlled conditions.

## Integration with TDD

Phase 4 hands off to the TDD workflow. The debugging skill answers "what's wrong and why." TDD
answers "how do we fix it and prove the fix works."

Debugging without TDD: you fix the bug but can't prove it stays fixed. TDD without debugging: you
write a test for the wrong root cause.
