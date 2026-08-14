# Behavior Wording

**Load this reference when:** writing or reviewing the Behaviors list of any plan task.

Write for the plan's audience: a skilled implementing agent with zero context for the codebase or
problem domain.

Write each behavior as an **observable outcome** — what renders, returns, or exits, under which
input or mode — never as the mechanism that produces it. "The `Note:` label uses the shared styling
helper" is satisfied by a call that styles nothing (`formatLabel(false)`); "the `Note:` label
renders yellow-underlined when color is on, plain when off" is not. Name a mechanism only in
addition to the outcome, never instead of it. Downstream verification checks exactly what the
sentence says — a mechanism-worded behavior gets verified at mechanism level and passes a broken
implementation.

For a behavior gated on a flag or mode (color, output format, verbosity, TTY), state the outcome of
**both branches** and spec test coverage for both — a fixture or assertion per branch. A behavior
whose tests exercise only one branch is unverified on the other.

Under length pressure, compress by dropping the mechanism, never the outcome. "Stay consistent with
the plan's concise style" is not a reason to word a behavior as a helper call.
