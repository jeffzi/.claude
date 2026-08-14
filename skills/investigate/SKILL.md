---
name: investigate
description: >
  Use when encountering any bug, test failure, crash, error, regression, or unexpected behavior,
  before proposing fixes. Also use when a fix attempt fails twice — stop guessing and start
  investigating. Use when you see a stack trace and don't understand the root cause. Not for
  applying the fix — use /fix (it loads this skill). Not for scanning files for latent bugs —
  use scan-bug.
argument-hint: "[error message, symptom, or failing test]"
# Model pinned: /investigate is a direct quality-floor entry point — hypothesis falsification degrades
# on cheaper tiers. Inert on the /fix path (Skill()-loaded inside fix's opus agent).
model: opus
effort: high
---

# Systematic Investigation

**Error / Symptom:** $ARGUMENTS

**Violating the letter of the rules is violating the spirit of the rules.**

Not for: known root cause with a failing test (use `Skill(tdd)`) or config/environment issues.

## The Iron Law

**No fixes without root cause investigation first.** About to change code because "it might fix it"?
Stop — that's guessing, not investigating. Guessing leads to: wrong fix, new bugs, wasted cycles,
masked root cause.

## Phase 1: Evidence Gathering

1. **Read the error** — full stack trace, exact message, line numbers; never a summary.
2. **Reproduce** — run the failing command yourself. Can't reproduce → can't verify a fix.
3. **Check recent changes** — `git log --oneline -10`, `git diff`.
4. **Trace data flow** — follow the actual values through the code path; read, don't assume. Crosses
   service boundaries → log what enters/exits each, run once to find WHERE, then analyze.
5. **Check assumptions** — types, nullability, initialization order, environment differences.

**Output:** a specific, falsifiable statement of what's wrong and where: "The error occurs because X
is Y when it should be Z, at `file:line`."

## Phase 2: Pattern Analysis

Compare what works with what doesn't:

| Technique              | How to apply                                                                                                                 |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Binary search          | Cut the problem space in half repeatedly — data correct at DB? at API? after serialization? Four tests eliminate 90% of code |
| Minimal reproduction   | Strip away one piece at a time; still fails → keep it removed. The bug becomes obvious in stripped-down code                 |
| Working backwards      | Start from the wrong output, trace back through the call stack to the first expected/actual divergence                       |
| Differential debugging | What changed? Compare working vs broken across code, environment, config, data, dependencies, timezone, network              |

**Output:** the specific difference between working and failing cases: "It works when X but fails
when Y, because Z differs."

## Phase 3: Hypothesis Testing

One hypothesis at a time. Minimal test. Verify. **Falsifiability:** a good hypothesis can be proven
wrong — no experiment could disprove it → not useful.

| Bad (vague)                         | Good (specific, testable)                                              |
| ----------------------------------- | ---------------------------------------------------------------------- |
| "Something is wrong with the state" | "State resets because component remounts on route change"              |
| "The timing is off"                 | "API call completes after unmount, updating unmounted component state" |
| "There's a race condition"          | "Two async ops modify same array without locking, causing data loss"   |

Per hypothesis: predict ("if H is true, I will observe X"), design the smallest test (one variable,
one change), run, conclude. Refuted → log it in Eliminated and return to Phase 1 — don't stack
hypotheses.

| Strong evidence                        | Weak evidence                              |
| -------------------------------------- | ------------------------------------------ |
| Directly observable in logs/output     | "I think I saw this fail once"             |
| Repeatable every time                  | Non-repeatable, intermittent               |
| Unambiguous (null, not undefined)      | "Something seems off"                      |
| Independent of caching/restart effects | Only after restart AND cache clear AND ... |

**Output:** a confirmed hypothesis with evidence: "Confirmed: X causes Y — changing X to Z resolves
the failure."

## Track What You've Eliminated

Log each eliminated hypothesis — `- [hypothesis] — disproved because [evidence]` — so dead ends stay
dead after compaction. Scan the list before testing a new hypothesis; re-investigating a ruled-out
one → stop.

## Red Flags — Catch Yourself

| You're thinking...                                              | Reality                                                                                                                                                         |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Let me just try this" / "The fix is obvious"                   | Obvious fixes that skip diagnosis mask the real issue. Actively seek disconfirming evidence: "What would prove me wrong?"                                       |
| "The error is misleading"                                       | The error is evidence, not opinion. A misleading error is still true about something — re-read it in full (Phase 1) before deciding which part is misdirection. |
| "I think it might be..." / "It's probably a race condition"     | The first explanation becomes your anchor. Generate 3+ hypotheses before investigating any.                                                                     |
| "This worked in a similar case"                                 | Treat each bug as novel until evidence says otherwise.                                                                                                          |
| "I've spent hours on this, just one more try"                   | Sunk cost. See Circuit Breaker — stop and reassess.                                                                                                             |
| Debugging your own code — you know what it was _supposed_ to do | Your intent masks what the code actually does. Read it as if someone else wrote it.                                                                             |
| "I already know what's wrong"                                   | If you did, you wouldn't need to investigate. Verify.                                                                                                           |
| "I'll investigate after I fix it"                               | You won't. The urgency disappears once it "works."                                                                                                              |
| "This is taking too long, just fix it"                          | Guessing takes longer. Systematic diagnosis is faster.                                                                                                          |
| "It's definitely this one thing"                                | "Definitely" without evidence is a guess.                                                                                                                       |
| "The fix works regardless of the cause"                         | Without confirming root cause, you can't know the fix is correct. The real issue resurfaces differently.                                                        |

## Circuit Breaker

**3+ failed hypotheses: stop and reassess.** You're chasing symptoms, not the disease.

| Signal                                     | Action                                                                                                                                                                                                                |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 3+ failed hypotheses                       | Question your mental model; re-read the error from scratch (fresh eyes); check a different layer                                                                                                                      |
| Each hypothesis points to a different area | The issue may be architectural, not localized — surface that distinction to the user                                                                                                                                  |
| Reassessment done                          | Surface: "I've tested N hypotheses without confirming a root cause. Here's what I've tried and ruled out. I think the issue may be in [area] — want me to investigate there, or do you have context that might help?" |
| Still no root cause after all phases       | Recommend monitoring/logging to capture the next occurrence; surface the ruled-out list — the user decides next steps                                                                                                 |

## Handoff

Root cause confirmed → `Skill(tdd)`; the confirmed root-cause statement is the failing test's input.
