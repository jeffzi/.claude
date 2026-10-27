---
name: test-core
description: >
  Use when writing, planning or reviewing tests in any language, or judging what code is tested:
  whether a test should exist, what it asserts, how many cases it needs, what it fakes. Not for TDD
  orchestration — use `Skill(tdd)`.
user-invocable: false
---

# Test Core

A test earns its place by failing when someone breaks logic this project wrote. Four principles
decide that. Violating the letter of these rules is violating their spirit.

## Dispatch

Load `Skill(test-{lang})` for the file's extension per `rules/skill-loading.md` › Language Dispatch;
it loads its own overlays. No row: Glob for `Skill(test-*)`, else note "no matching test skill".

## Test What the Project Computes

Before writing or keeping an assertion, name the line this project wrote that decides what it
checks, and an edit someone could make to that line by accident while changing something else. No
such line or edit: no test, and delete one you find.

Logic is something computed: an expression, a condition, a loop, parsing, cleanup, a value derived
from inputs.

No test, no permission needed; report `no test: <case>`:

- **A fixed value.** Anything written out by hand that the test would copy back: an attribute, a
  flag, an argument list, a dependency list, a `desc:` string, calls that always run in the same
  order. Only a deliberate edit changes it, and review guards deliberate edits, even when a stated
  guarantee rests on the value.
- **Fixed wording.** Assert what a message inserts (a name, value, path or count) and that the
  failure surfaced (exception type, stream, an exit status the project sets), never the text around
  them.
- **A dependency's behavior.** A library's parsing, rendering, `--help`, usage errors and their exit
  status; Terraform, Task or `set -e` failing on its own. The project's other packages, and a shared
  helper with its own tests, count as dependencies when seen through a caller. This holds when the
  dependency's output is the whole goal of the change.
- **Trivial wiring.** A call that turns on a dependency's feature (a parser for `--help`), or passes
  a value straight through: no accidental edit breaks it without breaking something tested.
- **Prose.** Read it; check the paths it names exist.
- **A fake's own output, or an absence.** A test that a removed name stays removed pins nothing. A
  check command (a tool that tests something else) gets one smoke test against a well-behaved fake.

Still tested: a value the project computes from inputs, even when passed to a dependency; a
guarantee its logic computes (an argument list built from inputs, never through a shell); a value
its logic branches on (a regex, tested through what it rejects).

A fake, stub or fixture is no larger than what the tests read; one larger than the project lines it
reaches costs more than it pins. Cut it down; size alone never deletes a test.

Never delete the last test of a branch of logic: first add a direct test at the module that owns it.
The last test of trivial wiring may go; there is nothing for it to catch.

## One Test per Distinct Branch

Each test or parametrized case takes a branch, crosses a boundary or exercises a rule its siblings
do not. Inputs that differ only in value take the same path: keep one per class. Vary inputs with
the language's parametrization, never a loop in the test body, unless the loop is the Act.

For every assertion, name the accidental edit that fails it while the sibling assertions on the same
Act still pass. None: drop it. Keep a precondition that stops a later assertion passing vacuously.

Traverse trivial behavior once per suite. Every test is isolated and deterministic.

## Test Through the Public API

Assert outputs, side effects and state through the public API, never internal calls, private
functions or data-structure shape. A private function the public API cannot reach is dead code or a
too-narrow API. Fake I/O, network, the clock and subprocesses, never the project's own
collaborators. Assert the outcome, not that a mock was called or in what order; a mock returning the
asserted value tests itself. Production code gains no method only tests call. Load
`references/anti-patterns.md` before adding or reviewing a mock.

## Test First Only for Logic

Logic starts with a failing test, seen failing for the expected reason (`Skill(tdd)`). A change
whose every part is in the no-test list above is edited directly and checked by running the suite.
That is the rule, not an exception to ask for. Adding coverage changes tests only; a bug it reveals
is surfaced, never encoded as expected.

## Shape

- Arrange, Act, Assert, separated by blank lines, one Act per test, no phase-label comments.
- The name states the behavior proven; "and" in a name means two tests. No docstrings on tests; one
  line on each fixture.
- New tests extend the feature's existing test file.
- Testing conventions in the project's CLAUDE.md or AGENTS.md bind like these rules.

## Rationalizations

| Excuse                                                                                         | Reality                                                                                             |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| "Something could break it": a mutant, a dropped flag, a name returning, the next file          | Only an accidental edit to computed logic counts. Deliberate edits and absences are review's.       |
| "A reviewer's note or a security property depends on this value"                               | A guarantee resting on a fixed value is a fixed value. Pin it where logic computes it.              |
| "It's what the change is for" / "remove our call and the test fails" / "users see this output" | It fails on someone else's output. Name the project line that decides the assertion.                |
| "There are tests here, so this change needs a red first"                                       | Only logic an accidental edit could break does. Trivial wiring gets no test; the suite is its gate. |
| "The mock was called" / "it returns the value" / "the private helper is covered"               | That pins wiring or the mock. Assert the outcome through the public API.                            |
| "Each case, copy or setup adds safety"                                                         | Another value on the same path is one case. A copy adds breakage, not proof.                        |
| "It looks redundant, so it goes"                                                               | Name what still fails if this choice changes, and what still reaches the branch.                    |
| "AAA is implied" / "phase labels help"                                                         | Check each test. Blank lines separate phases; labels restate them.                                  |
| "The tests pass and look reasonable"                                                           | Neither is a check. Apply each principle to each test.                                              |
