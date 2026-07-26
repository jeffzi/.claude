---
name: stryker-js
description: |
  Use when running mutation testing with StrykerJS on a JavaScript/TypeScript project — setting it
  up, improving a mutation score, deciding what to do with surviving mutants, or judging whether a
  survivor is an equivalent mutant. Also use for NoCoverage verdicts, Stryker dry-run timeouts, or
  "why does this mutant survive when a test asserts exactly that?" Not for ordinary line-coverage
  work.
argument-hint: "[source glob to mutate]"
---

# StrykerJS Mutation Testing

## Overview

Mutation score measures whether tests **detect behavior changes**, not whether they execute lines.
Every surviving mutant is a claim — "this change is invisible to your suite" — and each claim gets a
verdict before any test is edited: some survivors are test gaps, others are **equivalent mutants**
no test can ever kill.

Core discipline: **classify first, fix in batch, rerun Stryker exactly once as acceptance.**

## When to use

- Setting up Stryker on a vitest/jest project (one-off audit or recurring).
- "Improve the mutation score" / "kill these surviving mutants".
- Deciding whether a specific survivor is fixable, equivalent, or dead code.
- Stryker runs failing or absurdly slow (dry-run timeout, sandbox copying huge dirs).

**Not for:** raising line coverage (ordinary test work), fixing tests that already fail, or
non-JS/TS mutation tools.

## Phase 1 — Setup without touching the repo

Unless the user wants Stryker as a permanent dev dependency, leave zero trace:

- `npm install --no-save @stryker-mutator/core @stryker-mutator/vitest-runner` (official StrykerJS
  packages — stryker-mutator.io) — no package.json/lock churn, no uninstall step.
- Stryker config JSON goes in the **session scratchpad**, not the repo:
  `npx stryker run /path/to/scratchpad/stryker.conf.json`.
- A **stripped test-runner config** is usually required: Stryker runs test slices per mutant, so
  coverage thresholds, typecheck projects, and multi-project workspaces all break partial runs. It
  must live in the repo root (the sandbox copies the repo and resolves `vitest.configFile` there) —
  gitignore it and label it disposable in a header comment.

```jsonc
// scratchpad/stryker.conf.json
{
  "testRunner": "vitest",
  "vitest": { "configFile": "vitest.stryker.config.ts" },
  "mutate": ["src/parser/**/*.ts"],
  "coverageAnalysis": "perTest",
  "reporters": ["progress-append-only", "clear-text"],
  "dryRunTimeoutMinutes": 30,
  // repo-specific: list this repo's large non-build dirs/files, not these examples
  "ignorePatterns": [".claude", "docs/assets", "fixtures/large.jsonl"],
}
```

```ts
// vitest.stryker.config.ts (repo root, gitignored) — no thresholds, no typecheck project
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: { include: ["tests/unit/**/*.test.ts"], pool: "forks", isolate: false, testTimeout: 30000 },
});
```

| Option                                        | Why it matters                                                                                      |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `coverageAnalysis: "perTest"`                 | Runs only the tests covering each mutant — order-of-magnitude speedup on real suites                |
| `dryRunTimeoutMinutes: 30`                    | The instrumented initial run is far slower than a normal suite run; the default aborts large suites |
| `ignorePatterns`                              | The sandbox copies the project; exclude large non-build dirs (`.git`/`node_modules` auto-excluded)  |
| `mutate` globs                                | Scope the run by **files**, never by shrinking the mutator list — trimmed mutators hide gap classes |
| `reporters: progress-append-only, clear-text` | Log-file friendly progress plus a greppable final table and per-survivor `file.ts:line:col` lines   |

Do not invent config fields — check unfamiliar options against
`node_modules/@stryker-mutator/core/schema/stryker-schema.json`.

## Phase 2 — Baseline run

Run in the background, teed to a scratchpad log (`npx stryker run <conf> 2>&1 | tee <log>`). Extract
everything (score table, every `[Survived]` and `[NoCoverage]` line) from that file — never re-run
Stryker to re-filter output.

## Phase 3 — Classify every survivor before touching any test

For each survivor, state the **kill mechanism** first: "under this mutant, the output differs in way
X, so assertion Y on input Z fails." No mechanism stated = no test written. If you cannot name X,
you are probably looking at an equivalent mutant — prove observability before editing. This is real
analysis (grep callers, read the code path, check the fixture); a wrong bucket wastes a full
fix-and-rerun cycle.

| Bucket             | Signal                                                                                     | Action                                                       |
| ------------------ | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------ |
| **Test gap**       | Behavior is observable; no assertion covers it                                             | Add or strengthen a behavior-level assertion                 |
| **Fixture-blind**  | An assertion exists, but the fixture can't distinguish mutant from original                | Change the fixture; keep the assertion                       |
| **Equivalent**     | No valid input produces an observable difference (memo fast paths, uncollidable key joins) | Document it; never write a test for it                       |
| **Dead/defensive** | Guard unreachable because an upstream validator guarantees the invariant                   | Propose deleting the code (mutants vanish); the user decides |
| **Out of scope**   | Behavior is verified by a test tier Stryker doesn't run (integration, e2e, other runner)   | Document which tier covers it                                |

Worked example (fixture-blind): `arr.sort(cmp)` mutated to `arr.sort(() => undefined)` survives even
though a test asserts the output order. A comparator returning `undefined` coerces to `+0` — a
**stable no-op** that preserves input order. If the fixture is already in sorted order, the
assertion passes under the mutant. The kill is reordering the fixture, not a new test.

## Phase 4 — Plan, then execute

For more than a couple of survivors, load `Skill(write-plan)` and write the plan before editing: one
task per bucket-group, with the per-mutant kill mechanism recorded. Then execute the test edits,
verifying each with the **normal test command** — a killing test must pass against unmutated code
immediately. Green tests plus a stated kill mechanism is the per-fix verification; do not rerun
Stryker per fix or per batch.

Assert **behavior**, not the mutant's spelling — a regex copied from the mutated expression kills
the mutant but couples the test to implementation.

## Phase 5 — Acceptance rerun (exactly one)

After all fixes land and pass the project's full verification, rerun Stryker with the same config,
backgrounded and teed. Confirm from the log:

- every targeted mutant flipped to killed;
- mutants in deleted dead code vanished;
- zero NoCoverage (or each one documented);
- every remaining survivor sits in a documented bucket.

A targeted mutant that still survives means the kill mechanism was wrong — reclassify it before
editing anything else.

## Phase 6 — What stays behind

- The improved tests, committed via the project's normal verification-then-commit flow.
- The **survivor classification record** in the project's working-notes location — per remaining
  survivor: `file:line:col`, bucket, one-line reason. Without it, the next run re-litigates every
  accepted survivor from scratch.
- Nothing else: package.json/lock untouched, the gitignored runner config labeled disposable,
  scratchpad files left to expire.

## Reading verdicts

| Verdict               | Meaning                                                               |
| --------------------- | --------------------------------------------------------------------- |
| Killed                | A test failed under the mutant — good                                 |
| Survived              | All covering tests passed — classify it (Phase 3)                     |
| NoCoverage            | No test even executes the line — a coverage gap, not an assertion gap |
| Timeout               | Mutant likely caused an infinite loop — counted as killed             |
| Runtime/Compile error | Mutant produced invalid code — excluded from the score                |

## Common mistakes

| Excuse                                              | Reality                                                                                   |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| "Install with `--save-dev`, uninstall when done"    | Two lockfile churns and a forgotten uninstall. `--no-save` leaves nothing.                |
| "Rerun Stryker every few fixes for feedback"        | Each run costs minutes to hours. The normal test run is the fast feedback loop.           |
| "A test asserts order, so the sort mutant must die" | Fixtures lie. Verify the mutant can change the output _for that input_.                   |
| "It might be equivalent, but a test is cheap"       | A test that can never fail is worse than none — it's implementation coupling as coverage. |
| "Trim the mutator list to speed things up"          | Silently blinds you to whole gap categories. Scope with `mutate` globs + perTest.         |
| "Point Stryker at the normal vitest config"         | Coverage thresholds and typecheck projects fail per-mutant runs; the dry run dies.        |
| "The goal is 100%"                                  | The goal is: every survivor either killed or documented with a reason.                    |
| "Delete the logs and notes when done"               | Keep the classification record — it's the only defense against re-auditing equivalents.   |

## Red flags — STOP

- Writing a test with no stated kill mechanism.
- An assertion that mirrors the mutant's literal spelling instead of a behavior.
- Rerunning Stryker before all planned fixes have landed.
- Stryker packages present in package.json when you're done (unless the user asked for them).
- Declaring the run "done" with unclassified survivors in the log.
