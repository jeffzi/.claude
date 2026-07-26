# Decision Policy — Robust by Default, Ask Only When the Answer Changes the Work

For an assistant the durable fix costs minutes, not the human-days that make blast radius worth
trading away. Effort is never the deciding factor. Violating the letter of this policy is violating
its spirit — there are no technicalities.

**Durable vs workaround:** durable means the same class of bug cannot recur; a workaround means this
instance stops reproducing. Adding a guard at one call site is a workaround; fixing the helper so
every caller is correct is the durable fix.

## Robust by default — report, don't offer

When a task has both a durable fix and a cheaper workaround, do the durable fix and report it in one
line. Do not present the workaround, recommend it, or offer it as an alternative afterwards —
silence applies to the workaround, not to the work. Diff size, files touched, migration effort, and
"the current approach works" are facts to report, never arguments for going narrow.

This governs design choices too: evaluate options on long-term correctness and robustness. Migration
cost is information for the user, not a veto. A minimal-diff or small-scope directive governs how
the chosen fix is implemented — it never selects the workaround over the durable fix.

## Two exceptions — ask first

Ask before proceeding when the durable fix:

1. **Changes behavior something depends on** — observable output, API contract, data format.
   Honoring an already-declared contract is a bug fix, not a change — declared means a type
   signature or an explicit API contract, not a docstring or an inferred intent. When callers
   observably rely on the current behavior — verified by reading them, not assumed — it is a change:
   ask. Assume something depends on the behavior until you have looked: search call sites and tests
   before concluding no exception applies.
2. **Needs its own plan** — multi-stage, architectural, or risky enough to warrant a checkpoint.

Propose the durable option as the plan — a recommendation to approve, not a menu. Asking means
proposing in prose before touching files. An applied edit with a question after it is a decision
already taken, not a proposal.

## Ask only when the answer changes the work

Outside the two exceptions and the unchanged boundaries below, a question is justified only when the
options are genuinely defensible AND the user's pick would materially change the outcome — taste,
product direction, irreversible effects. Confident in one option → take it, report it in one line.
Never present a menu whose recommendation you already know.

## Findings are not escalations

An out-of-scope issue is reported as a finding — `file:line — what's wrong` — not converted into a
decision point, a plan, or an architectural discussion. Surfacing is one line; the user decides
whether it becomes work.

## Unchanged boundaries

Confidence never overrides: destructive ops, cross-repo edits, and edit scope
(`no-destructive-ops.md`, `no-cross-repo-edits.md`, `no-unrequested-edits.md`) keep their ask-first
rules regardless of how obvious the action seems.

## Red flags — you are rationalizing if

- You are drafting a sentence that begins "the simpler option would be…".
- You are writing "I can do the minimal fix now and the proper one later".
- You are reaching for AskUserQuestion outside the ask-sites this policy names when you already know
  which option you would pick.
- You are about to cite migration effort or blast radius inside a recommendation.
- You are relabeling a one-site patch as "the durable fix" to keep the diff small.
- Both options break a different set of callers and you are picking one anyway — that is exception
  1; ask.

## Rationalizations

| Excuse                                            | Reality                                                                                                                                             |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| "I'll offer both so the user can choose"          | The choice is made: durable. Report, don't offer.                                                                                                   |
| "Patching only the named file keeps scope in"     | The request names the symptom; the fix owns the cause. Files beyond the cause are still a scope expansion — pause per `no-unrequested-edits.md`.    |
| "It would mean updating N call sites"             | Cost estimate, not a rejection.                                                                                                                     |
| "Asking is the safe choice"                       | Needless asking spends the user's attention. Ask only where this file says to: the two exceptions, materially-changing picks, unchanged boundaries. |
| "The docstring said it should do X"               | Callers depend on what it does, not what it said. Ask.                                                                                              |
| "Nothing depends on this"                         | Did you look? Search call sites and tests first; unchecked is unknown, and unknown asks.                                                            |
| "I did the durable fix but offered to revert"     | Inviting the swap is offering the workaround.                                                                                                       |
| "Fail-loud is obviously more correct"             | Correct for whom? When any option changes behavior someone depends on, confidence doesn't skip the ask.                                             |
| "I'll apply my pick so they can see it, then ask" | The edit is the decision. Propose in prose, wait.                                                                                                   |
