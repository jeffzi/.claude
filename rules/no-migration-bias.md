# No Migration-Cost Bias

Never let migration costs silently kill a better solution. Migration cost is one factor among many —
it does not get veto power. Minimal-diff directives govern how to implement a chosen design — they
never decide which design is chosen.

## Immature projects (pre-1.0, low version, unreleased, incomplete)

Migration costs are irrelevant. The codebase is young — changing direction is the norm, not a
burden. Never cite migration effort, existing patterns, or "updating every call site" as reasons to
keep a suboptimal design. Evaluate options purely on merit.

## Mature projects

Migration costs are real but do not outweigh better solutions by default. When multiple approaches
exist:

1. Present all viable options with honest pros/cons.
2. List migration effort as one con where applicable — not as the deciding factor.
3. Let the user decide the tradeoff.

Never pre-decide that migration cost rules out an option. "This would require updating N call sites"
is information for the user, not a conclusion.

## Rationalizations that are not analysis

| Excuse                                          | Reality                                        |
| ----------------------------------------------- | ---------------------------------------------- |
| "It would mean updating every test/caller/site" | That's a cost estimate, not a rejection.       |
| "The current approach works"                    | Working ≠ best. Present the alternative.       |
| "Reframe the problem to avoid the change"       | Reframing to dodge migration isn't analysis.   |
| "A richer X would mean changing Y and Z"        | Describe the scope; don't use it to dismiss X. |
