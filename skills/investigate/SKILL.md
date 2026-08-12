---
name: investigate
description: >
  Use when encountering any bug, test failure, crash, error, regression, or unexpected behavior,
  before proposing fixes. Also use when a fix attempt fails twice — stop guessing and start
  investigating. Use when you see a stack trace and don't understand the root cause.
argument-hint: "[error message, symptom, or failing test]"
# Model pinned: /investigate is a direct quality-floor entry point — hypothesis falsification degrades
# on cheaper tiers. Inert on the /fix path (Skill()-loaded inside fix's opus agent).
model: opus
effort: high
---

# Systematic Investigation

**Error / Symptom:** $ARGUMENTS

**Violating the letter of the rules is violating the spirit of the rules.**

## When NOT to Use

- Root cause is already known and you have a failing test — go straight to TDD
- Configuration or environment issues — just fix the config

## The Iron Law

**No fixes without root cause investigation first.**

If you're about to change code because "it might fix it" — stop. That's guessing, not investigating.
Guessing leads to: wrong fix, new bugs, wasted cycles, masked root cause.

## Three Phases

### Phase 1: Evidence Gathering

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

Compare what works with what doesn't. Use these techniques:

**Binary search** — Cut the problem space in half repeatedly. Data correct at DB? Yes. Correct at
API? Yes. Correct after serialization? No. Found: serialization layer. Four tests eliminate 90% of
code.

**Minimal reproduction** — Strip away everything until the smallest code reproduces the bug. Remove
one piece at a time. If it still fails, keep it removed. The bug becomes obvious in stripped-down
code.

**Working backwards** — Start from the wrong output, trace backwards through the call stack. Find
the first point where expected and actual values diverge.

**Differential debugging** — What changed? Compare working vs broken across: code changes,
environment, config, data, dependencies, timezone, network conditions.

**Output:** The specific difference between working and failing cases. "It works when X but fails
when Y, because Z differs."

### Phase 3: Hypothesis Testing

One hypothesis at a time. Minimal test. Verify.

**Falsifiability requirement** — A good hypothesis can be proven wrong. If you can't design an
experiment to disprove it, it's not useful.

| Bad (vague)                         | Good (specific, testable)                                              |
| ----------------------------------- | ---------------------------------------------------------------------- |
| "Something is wrong with the state" | "State resets because component remounts on route change"              |
| "The timing is off"                 | "API call completes after unmount, updating unmounted component state" |
| "There's a race condition"          | "Two async ops modify same array without locking, causing data loss"   |

**For each hypothesis:**

1. **Predict** — "If H is true, I will observe X."
2. **Design the smallest test** — one variable, one change.
3. **Run it** — observe. Record what actually happened.
4. **Conclude** — does this support or refute H?
5. **If refuted** — document it in Eliminated, back to Phase 1 with new evidence. Don't stack
   hypotheses.

**Evaluate evidence quality:**

| Strong evidence                        | Weak evidence                              |
| -------------------------------------- | ------------------------------------------ |
| Directly observable in logs/output     | "I think I saw this fail once"             |
| Repeatable every time                  | Non-repeatable, intermittent               |
| Unambiguous (null, not undefined)      | "Something seems off"                      |
| Independent of caching/restart effects | Only after restart AND cache clear AND ... |

**Output:** A confirmed hypothesis with evidence. "Confirmed: X causes Y. Evidence: changing X to Z
resolves the failure."

## Track What You've Eliminated

Document each eliminated hypothesis before moving on. This prevents re-investigating dead ends,
especially after context compression.

Format: `- [hypothesis] — disproved because [evidence]`

Before testing a new hypothesis, scan the eliminated list. If you're about to re-investigate
something already ruled out, stop.

## Red Flags — Catch Yourself

| You're thinking...                                                        | Reality                                                                                                                   |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| "Let me just try this" / "The fix is obvious" / "The error is misleading" | Obvious fixes that skip diagnosis mask the real issue. Actively seek disconfirming evidence: "What would prove me wrong?" |
| "I think it might be..." / "It's probably a race condition"               | The first explanation becomes your anchor. Generate 3+ hypotheses before investigating any.                               |
| "This worked in a similar case"                                           | Treat each bug as novel until evidence says otherwise.                                                                    |
| "I've spent hours on this, just one more try"                             | Sunk cost. See Circuit Breaker — stop and reassess.                                                                       |
| Debugging your own code — you know what it was _supposed_ to do           | Your intent masks what the code actually does. Read it as if someone else wrote it.                                       |
| "I already know what's wrong"                                             | If you did, you wouldn't need to investigate. Verify.                                                                     |
| "I'll investigate after I fix it"                                         | You won't. The urgency disappears once it "works."                                                                        |
| "This is taking too long, just fix it"                                    | Guessing takes longer. Systematic diagnosis is faster.                                                                    |
| "It's definitely this one thing"                                          | "Definitely" without evidence is a guess.                                                                                 |
| "The fix works regardless of the cause"                                   | Without confirming root cause, you can't know the fix is correct. The real issue resurfaces differently.                  |

## Circuit Breaker

**3+ failed hypotheses:** Stop and reassess. You're chasing symptoms, not the disease.

- Question your mental model of the code
- Re-read the error from scratch (fresh eyes)
- Check if the bug is in a different layer than you think
- If each hypothesis leads to a different area, the issue may be architectural — not a localized
  bug. Surface this distinction to the user.
- Surface to the user: "I've tested N hypotheses without confirming a root cause. Here's what I've
  tried and ruled out. I think the issue may be in [area] — want me to investigate there, or do you
  have context that might help?"
- **Still no root cause after completing all phases:** recommend monitoring or logging to capture
  the next occurrence, and surface to the user with the ruled-out list — they decide next steps.

## Handoff

Investigation answers "what's wrong and why." Once root cause is confirmed, hand off to `Skill(tdd)`
for the fix — the confirmed root cause statement becomes input for writing the failing test.
