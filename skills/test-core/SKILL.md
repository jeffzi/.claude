---
name: test-core
description: >
  Use when writing or reviewing tests in any language. Covers test behavior vs. implementation, AAA
  structure, merge/redundancy rules, false-coverage detection (including tests of a dependency's own
  behavior), parametrization, and mocking anti-patterns. Not for TDD orchestration — use
  `Skill(tdd)`.
user-invocable: false
---

# Test Core

Test behavior, not implementation. A refactor that preserves observable behavior should never break
a test. Violating the letter of these rules is violating their spirit.

## Dispatch

**Process:**

1. Read the target file's extension.
2. Find its row in `rules/skill-loading.md` → **Language Dispatch for test-\* and code-\*** (read
   that file if it is not already in your context).
3. Load the matching **Test skill** via `Skill(test-{lang})`.
4. That skill's **Domain Skill Detection** section loads overlays automatically (`test-py` sees
   `import polars` → loads `test-polars`). Do not pre-compute overlays.
5. No row for the extension → check for `Skill(test-*)` via Glob; if none matches, note "no matching
   test skill" and proceed using project conventions.

## Principles

### 1. Arrange-Act-Assert

Every test function has three distinct phases, in order:

1. **Arrange** — set up preconditions and inputs
2. **Act** — execute the behavior under test (single action)
3. **Assert** — verify the expected outcome

No logic between phases. No assertions in Arrange. One Act per test. "And" in the test name? Split
it. Name the behavior the test proves, never an ordinal (`test1`). Separate phases with a blank
line, not comments — `// Arrange`, `// Act`, `// Assert` labels restate what the structure already
shows. Remove bare labels; strip the prefix from comments that carry a real explanation. No
docstrings on test functions — the name carries the intent. Every fixture gets a one-line docstring.

### 2. Test Behavior, Not Implementation

Assert what the code **does** (outputs, side effects, state changes), never **how**.

| Fragile (implementation-coupled)               | Resilient (behavior-focused)                         |
| ---------------------------------------------- | ---------------------------------------------------- |
| Assert internal method was called              | Assert observable output or state changed            |
| Mock private helpers or internal collaborators | Mock only at system boundaries (I/O, network, clock) |
| Verify exact call count/order on mocks         | Verify end result                                    |
| Assert internal data structure shape           | Assert public API contract                           |
| Snapshot an entire object for one field        | Assert only the relevant field(s)                    |
| Import and test private functions directly     | Drive coverage through the public API                |

### 3. Never Test Private Functions Directly

A private function unreachable through the public API is dead code or a too-narrow API — fix the
design, don't test internals.

```python
# BAD: testing private function directly to pad coverage
from mymodule._internals import _parse_discount_rule
assert _parse_discount_rule("15%") == 0.15

# BAD: asserting internal wiring instead of outcome
mock_engine.calculate_percentage.assert_called_once_with(0.15)

# GOOD: drives coverage through the public API, survives refactors
assert checkout.total == 85.00  # 15% discount applied to $100
```

### 4. False Coverage

Mocking a collaborator and asserting the mock's own return value exercises zero real logic. **If
removing the production code wouldn't fail the test, the test covers nothing.**

**A removed feature gets removed tests — never a test that it stays removed.** A test asserting a
dropped parameter is rejected, a deleted function no longer exists, an old kwarg raises `TypeError`,
or a signature lacks a name pins an absence, not a behavior. There is no production code for it to
cover, and it breaks the moment any legitimate parameter is added. When a feature is dropped, delete
its tests. When you find such a test, delete it — it is never renamed, kept, or "tightened".

**A dependency's behavior is not yours to test.** For every test, name the line this project wrote
that _decides_ what the test asserts. A pass-through call into a library, the standard library, or
an external tool decides nothing: when it is the only project line involved and the assertion is the
dependency's own rendering, parsing, environment handling, or error handling, the test covers the
dependency. Don't write it; when you find one, delete it. That the test fails once the call is
removed changes nothing — it fails because someone else's output changed.

The project's own other packages count as dependencies here. When a caller's test asserts how a
package it calls renders, parses, or styles, it re-checks the called package, whose own tests own
that behavior. The caller pins only what it chose: the marker, argument, or wording it passed in.

A choice the project makes _through_ a dependency is project behavior and stays pinned when the
project computes it (§ 4a): the argument list it builds from inputs, the field tags it declares, the
entries it turns on or off, a guarantee it documents ("never through a shell"). Assert it in the
project's own terms — the argv sent, the value decoded, the commands listed. An assertion that can
only be written in the dependency's encoding (escape codes, padding, column layout) has nothing of
the project's to pin.

When the only failing test available for a change asserts a dependency's output — one option handed
to a library — write no test: say why none covers the change and ask for the exception to the
test-first rule. Never manufacture a test of the dependency to put a red-green in the diff.

**Name the regression.** For every assertion, name an edit someone could make by accident (§ 4a) to
a line of logic this project wrote that fails it while every earlier or cheaper check still passes.
No such edit → delete the assertion. The usual cases with none: it is implied by sibling assertions
on the same Act; it re-checks a called package's behavior; it repeats a pin another test already
makes on the same path. Two things look redundant and are not:

- **A choice no other assertion can see.** Before calling a choice "already pinned", name the
  assertion that fails when the choice changes. A count marked as a tally and the same count printed
  bare produce identical plain text — only the styled check pins the marker.
- **A precondition.** An assertion that proves the code under test ran, so a later assertion cannot
  pass vacuously, stays — even when another test checks the same fact.

### 4a. What Deserves a Test

A test is warranted only when you can name **an edit someone could make by accident** — while
changing something else — to a line of logic this project wrote, and the test fails on it. Logic
means something computed: an expression, a condition, a loop, cleanup, parsing, a value derived from
inputs. Naming a mutant is not enough: the edit must be one a person makes without meaning to.

No test, by rule — no user grant needed:

- **Fixed configuration**: a value, reference, or omitted block that changes only when someone edits
  that line — a hard-coded attribute, a lifetime, a flag, a resource reference, a block left out on
  purpose, an argv entry written out in a Taskfile or hook config, a `desc:` string, a dependency
  list. The test for it: would the test fail only if someone edits the value the test itself copies?
  Then changing it is deliberate, and review guards it. This holds even when a stated outcome or
  guarantee depends on the value: a note that the outcome "no longer holds" or "would pass every
  test" without it describes a deliberate edit to that line, not an accident.
- **A message's fixed wording.** Assert the parts of a message the code computes — the name, value,
  path, or count it inserts — and that the right failure surfaced (error type, exit code, stream).
  Never pin the fixed text around them word for word: rewording is a deliberate edit. This holds
  when the repo builds the expected text from a shared constant or helper too: assert `suggestion in
  hint`, never `hint == f"did you mean {suggestion}? {HINT}"`.
- **Dependency behavior.** Terraform failing an apply when a provisioner fails, Task stopping at a
  failing command, a library's parsing or errors, a linter's exit code.
- **Prose.** Markdown, SKILL.md, README text. Verify by reading that the paths it names exist.
- **A shared helper's behavior through a caller.** The helper's own tests own it; a caller's tests
  never repeat a missing setting, a client that cannot be built, or hidden terminal input.
- **A fake's or stub's own output.** A check command (a tool whose job is to test something else)
  gets one smoke test against a well-behaved fake, not a case per failure it reports. A new failure
  it detects adds no test case. A per-failure table already in its test file is debt, not a project
  convention (§ 7 covers written rules, not existing tests): never add a row to it.

Still tested: argv or values the project _computes_ from inputs, conditions, cleanup and restore
paths, every branch of project logic. "It is passed to a dependency" never exempts a computed value,
and "it is fixed configuration" never exempts a value the project's logic branches on (a validation
regex is tested through what it rejects, never through its text).

### 5. Minimum Tests, Maximum Coverage

| Merge when                          | Keep separate when    |
| ----------------------------------- | --------------------- |
| Same code path, different inputs    | Different code paths  |
| Related edge cases (None, empty, 0) | Complex setup differs |
| Same behavior across APIs           | Tests need isolation  |

**A case earns its row.** Each test or parametrized case must take a different branch, cross a
different boundary, or exercise a different rule than its siblings. Inputs that differ only in value
— another invalid character, the same character at another position, another casing, another sample
of the same class — take the same path: keep one. Count the classes first, then write one case per
class.

Test trivial behavior only to traverse a code path — **once** across the entire suite: one
parametrized test per call shape (or one test with grouped asserts per subject), never one test
function per assert or a repeated Act sliced across tests.

Every test is **isolated** — same result in any run order — and **deterministic**.

### 6. Parametrize Over Loops

Same code path, varying inputs → the language's parametrization mechanism, **never** an in-test loop
— unless the loop _is_ the behavior under test (then it is the Act)
([fix per language](references/anti-patterns.md#anti-pattern-5-stacked-assertions-over-varying-inputs)).

### 7. Project Conventions Bind Equally

Testing conventions in the project's CLAUDE.md (and imports like AGENTS.md) bind with equal force:
follow them when writing, cite them when reviewing (`CLAUDE.md: "<quoted convention>"`). Only
imperative rules about test content qualify — command references and build instructions are
documentation.

## When Adding Coverage

Gap-filling is test-only: never modify implementation files. STOP and surface any bug a new test
reveals — never encode it as "expected" or tweak inputs to dodge it. Apply the
[merge table](#5-minimum-tests-maximum-coverage) before each new test function; extend the feature's
existing test file, never `*_coverage`/`*_extra` parallel files.

## Mocking Anti-Patterns

Load `references/anti-patterns.md` before adding or reviewing mocks, adding a test-only method to
production code, or varying inputs over one code path. Mocks are tools to isolate, not things to
test.

## Universal Rationalizations

| Excuse                                   | Reality                                                         |
| ---------------------------------------- | --------------------------------------------------------------- |
| "I can name a mutant, so test it"        | Only an accidental edit to logic counts. See § 4a.              |
| "A reviewer said no test pins it"        | § 4a decides, not the reviewer. Fixed config stays untested.    |
| "A stated outcome depends on this value" | Still fixed configuration: only a deliberate edit changes it.   |
| "Tests look reasonable"                  | "Reasonable" skips pairwise comparison. Apply the merge table.  |
| "AAA is implied"                         | Implicit ≠ verified. Check phase separation per test.           |
| "AAA comments help readability"          | A blank line separates phases; the label restates the obvious.  |
| "Each edge case deserves its own test"   | Same code path + different inputs = merge. See merge table.     |
| "I need to verify the mock was called"   | Assert the outcome, not the wiring. See behavior-vs-impl table. |
| "Testing _func directly boosts coverage" | Coverage via private imports is fake. Drive through public API. |
| "The mock returns the right value"       | That tests the mock, not the code. See false coverage note.     |
| "It guards against re-adding the param"  | Code review guards that. An absence has no behavior. Delete it. |
| "The linter would have caught this"      | Linters miss redundancy, naming, philosophy, structure.         |
| "Remove our call and the test fails"     | It fails on the library's output. Name the line that decides.   |
| "Test-first needs a red; one is at hand" | A red on someone else's code proves nothing. Ask the exception. |
| "It asserts the command's real output"   | Output the project does not compute is not its behavior.        |
| "The plain text already pins the marker" | Name the assertion that fails if the marker changes.            |
| "It's only a sanity check before assert" | A precondition that stops a vacuous pass stays. Keep it.        |
| "Users see this styling in our output"   | The styling package owns that test. Pin only your marker.       |
| "Loop is cleaner than parametrize"       | Parametrize shows all cases; loop stops at first failure.       |
| "I scanned the file and found no issues" | Scanning ≠ rule-by-rule. Walk the checklist rule-by-rule.       |

## Red Flags

STOP and re-check if:

- A test asserts on an element whose test ID ends with `-mock`
- A method is only called from test files
- Mock setup is >50% of the test body
- Test fails when you remove a mock (and the product code didn't change)
- You cannot explain, in one sentence, what behavior the test proves
- A loop inside the test body performs the same assertion with different inputs
- A test imports from `_internals` / `_private` / other private modules
- A test asserts a name is **absent** — `not in signature`, `hasattr(...) is False`, `TypeError` on
  a kwarg that was removed
- A test has `// Arrange`, `// Act`, or `// Assert` phase-label comments
- The only project line a test depends on is a call into a library, and the assertion is written in
  the library's encoding — escape codes, layout, its reading of the environment
- You cannot name an edit to project code that fails an assertion while every earlier or cheaper
  check still passes
- A caller's test asserts how another package of the project renders, parses, or styles
