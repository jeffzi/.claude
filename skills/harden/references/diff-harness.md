# Diff Harness — Baseline and Gate Mechanics

Applies only when the project harness defines a Diff Harness. The general framework is fixed; the
commands come from the harness.

## Task 0 — baseline snapshot, always first

Run the harness's baseline-snapshot commands. Always from a clean working tree — commit first;
uncommitted edits leak into the baseline.

## Per-task gate

Run the harness's per-task gate commands. These rebuild, diff against the baseline, and run the
relevant tests. The diff gates the output; the tests gate behavior the diff cannot see (helper
renames, fixture imports, anything structural). Catching a regression only at a round-end gate loses
per-task attribution.

## Re-baseline after every accepted non-empty diff

Once a task whose diff was accepted (a bug fix or a deliberate output change) is committed, re-run
the **full** Task 0 block from the committed HEAD. Otherwise every later task's gate re-reports the
accepted hunks and forces hunk-by-hunk eyeballing — the judgment the gate exists to replace.
Re-cutting from a committed HEAD is always safe; the same recovery applies if the baseline is wiped
mid-round.
