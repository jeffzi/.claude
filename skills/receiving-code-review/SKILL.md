---
name: receiving-code-review
description: Use when receiving structured code-review feedback — PR comments, a reviewer's findings, or output from a review agent — and deciding what to implement. Apply before acting on suggestions, especially when feedback is unclear, multi-item, or technically questionable. Not for producing reviews (use vet-code / bug-scanner / preflight for that).
effort: high
---

# Code Review Reception

The no-performative-agreement stance is always on (`rules/receiving-feedback.md`). This skill is the
workflow for handling a _structured_ review — multiple items, an external reviewer, a PR thread.
Verify before implementing; ask before assuming; technical correctness over social comfort.

## The reception pattern

```text
1. READ      — the complete feedback, without reacting
2. UNDERSTAND — restate each item in your own words, or ask
3. VERIFY     — check each against codebase reality
4. EVALUATE   — is it sound for THIS codebase?
5. RESPOND    — technical acknowledgment or reasoned pushback
6. IMPLEMENT  — one item at a time, test each
```

## Stop on unclear — before any partial work

If _any_ item is unclear, stop. Do not implement the clear ones yet.

> Items may be related. Partial understanding produces wrong implementation.

Right: "I understand items 1, 2, 3, 6. I need clarification on 4 and 5 before implementing." Wrong:
implement 1, 2, 3, 6 now and ask about 4, 5 after.

## External reviewers — verify the 5 points

A reviewer (human or agent) sees a slice, not the whole. **Never implement a suggestion before
clearing all 5 points** — not even when the reviewer is senior, confident, or "obviously right":

1. Technically correct for _this_ codebase?
2. Breaks existing functionality?
3. Is there a reason for the current implementation?
4. Works on all targeted platforms / versions?
5. Does the reviewer have full context, or only the diff?

If it seems wrong → push back with technical reasoning. If you can't verify → say so and ask for
direction. If it conflicts with a prior decision the user made → stop and raise it before acting.

External feedback = suggestions to evaluate, not orders to follow.

## YAGNI check for "do it properly"

When a reviewer says "implement this properly" / "add full handling," grep for actual usage first:

```text
unused → "Nothing calls this. Remove it (YAGNI)?"
used   → implement properly
```

## Implementation order

For multi-item feedback, after clarifying everything unclear:

1. Blocking issues (breaks, security)
2. Simple fixes (typos, imports)
3. Complex fixes (refactors, logic)

Test each fix individually; verify no regressions before the next.

## When to push back

Suggestion breaks existing behavior · reviewer lacks context · violates YAGNI · technically wrong
for this stack · legacy/compat reasons exist · conflicts with a prior architectural decision.

Push back with technical reasoning and a reference to the test or line that shows it — not
defensiveness. If the issue is architectural, raise it with the user rather than deciding alone.

## GitHub thread replies

When replying to an inline PR review comment, reply _in the thread_, not as a top-level PR comment:

```sh
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies -f body='...'
```

## Common mistakes

| Mistake                        | Fix                                                                    |
| ------------------------------ | ---------------------------------------------------------------------- |
| Performative agreement         | State the requirement, or just act (see `rules/receiving-feedback.md`) |
| Blind implementation           | Verify against the codebase first                                      |
| Batch without testing          | One at a time, test each                                               |
| Assuming the reviewer is right | Check whether it breaks things                                         |
| Avoiding pushback              | Technical correctness over comfort                                     |
| Partial implementation         | Clarify all items first                                                |
| Can't verify, proceed anyway   | State the limitation, ask for direction                                |
