# Lint Suppressions — Fix the Code, Not the Config

Treat lint and type-check configuration as fixed. Never add to an ignore list, disable a rule, lower
a severity, or exclude a file to get a check passing — fix the code instead. This covers every
checker: linters, type checkers, formatters, spell checkers, dead-code and security scanners.

## When a suppression is warranted

Only when the finding is a genuine false positive or the rule cannot apply — a generated file, a
documented upstream bug, a deliberate test fixture. Then suppress at the narrowest scope: an inline
directive on the offending line, with a reason, never a config-level ignore.

## Config-level ignores require explicit user approval

When the same inline directive keeps recurring for the same rule, that is a signal the rule may
deserve a config-level ignore — propose it to the user and wait for explicit approval. Never promote
a suppression into shared config on your own, and never add a config ignore as the first resort.

## Rationalizations that are not a legit reason

| Excuse                                        | Reality                                            |
| --------------------------------------------- | -------------------------------------------------- |
| "The rule is too strict here"                 | Strictness is the project's choice, not yours.     |
| "It's faster to ignore than to fix"           | Convenience is never a reason to suppress.         |
| "There are already similar ignores in config" | Existing ignores were approved; yours wasn't.      |
| "I'll suppress now and fix properly later"    | Fix now, or surface the finding and let user pick. |
| "The inline directive appears five times"     | That's a proposal to make, not approval to act on. |
