# Plan Review and Claim Verification

**Load this reference when:** a draft plan is ready and the pre-presentation review passes are due.
Send the two agents below in a single message so they run in parallel.

## Plan Review (advisory)

For plans with 2+ tasks, dispatch one **Agent** call with `subagent_type: general-purpose` and
`model: sonnet`, passing the spec and the draft plan, to check completeness, spec alignment, and
task decomposition. The model is pinned because this agent checks a written plan against a supplied
spec rather than diagnosing anything. Max 3 review iterations, then surface to user. Reviewers are
advisory.

For smaller plans, review inline before presenting to the user.

## Verify Plan Claims (mandatory)

A plan asserts facts about the codebase — files it will modify already exist, named symbols are
present, the current code behaves as described, a pattern to follow lives where the plan says. A
plan built on a stale or wrong assumption sends the implementer down a dead end. Before presenting
the plan, verify these factual claims independently. This pass is **mandatory** on every plan,
including test-only ones.

Dispatch a single **Agent** tool call with `subagent_type: claim-reviewer` (do NOT set model — the
agent defines its own). Extract one claim per checkable assertion the plan makes about existing
code:

```text
Claim N: [the plan's factual assertion about the codebase]
Location: [file:line or symbol the claim names, if any]
```

The agent returns a `### Claim N` block per claim (`Verdict: Verified | Refuted | Unsubstantiated`,
`Score`, `Evidence`, `Reasoning`). For any `Refuted` or `Unsubstantiated` verdict, re-check the
claim against the code once: if the reviewer is right, correct the plan — fix the path, re-scope the
task, or drop the assumption — before presenting it; if your re-check confirms the claim, keep it
and cite the confirming evidence in the plan. Do not feed the agent claims about code the plan will
_create_; it can only verify what exists now.
