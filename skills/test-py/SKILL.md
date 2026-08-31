---
name: test-py
description: >
  Use when writing Python tests with pytest. Apply for
  fixtures, mocking, parametrization, property-based
  testing, flaky tests, test isolation issues, data
  validation, AssertionError debugging, or any
  test_*.py files.
user-invocable: false
---

# Python Testing with pytest

**This skill extends `Skill(test-core)`.** Universal principles (AAA, behavior-vs-implementation,
merge/redundancy, parametrize-over-loops, mocking anti-patterns) live in `test-core`. This file adds
pytest-specific syntax, fixtures, plugins, and pitfalls.

**Load `Skill(code-py)` and apply its rules.** Exception: test functions don't need `-> None`
annotations.

## Domain Skill Detection

When reviewing or writing test files, check imports for domain-specific libraries. If detected, load
the corresponding skill for library-specific testing patterns:

| Import pattern                                 | Skill to load  |
| ---------------------------------------------- | -------------- |
| `import polars` / `from polars.testing import` | `test-polars`  |
| `from rich.` / `import rich` / `import pyte`   | `test-py-rich` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Mandatory Rules

### 1. Test Names Use the Full `test_<function>_when_<condition>_does_<expected>` Form

Don't abbreviate. `test_parse_when_input_empty_does_raise_valueerror` is better than `test_parse_1`,
and `test_create_user_when_email_taken_does_raise` is better than `test_create_user_dup`.

### 2. Function-Scoped Fixtures by Default

Isolation over speed. Broader scopes only for truly expensive setup — and never with mutable state.

### 3. No Classes for Logical Grouping

Use comment section headers to organize tests by topic. Reserve classes **only** for shared
`autouse` fixtures or class-scoped setup that can't be a module-level fixture.

```python
# BAD — class as a section header
class TestMoveObject:
    def test_move_object_updates_position(self): ...
    def test_move_object_clamps_to_bounds(self): ...

# GOOD — comment sections + plain functions
# ---------------------------------------------------------------------------
# move_object
# ---------------------------------------------------------------------------

def test_move_object_updates_position(): ...
def test_move_object_clamps_to_bounds(): ...
```

### 4. Always `autospec=True` When Patching

Catches typos in mocked method names, wrong argument counts, and missing methods — at call time, not
in production.

```python
# BAD — silently passes when the method is renamed
mocker.patch("myapp.service.Client.fetch_data")

# GOOD — fails loudly on rename or wrong arg count
mocker.patch("myapp.service.Client.fetch_data", autospec=True)
```

## Parametrization Syntax

Use `pytest.param(..., id="...")` to name non-obvious cases:

```python
@pytest.mark.parametrize("a,b,expected", [
    (1, 2, 3),
    pytest.param(-1, 1, 0, id="opposite-signs"),
])
```

## Data Testing Patterns

Prefer `hypothesis` property-based testing over hardcoded data. Use `polyfactory` to generate
pydantic/dataclass instances only for complex nested models. With `moto`, import the modules under
test AFTER `@mock_aws` is active — importing boto3 clients before the mock binds them to real AWS.

**Hardcoded data only for**: realistic inputs from production (e.g., actual JSON events, real API
responses).

**Seeding**: Set ALL sources — `random.seed()`, `np.random.seed()`, `torch.manual_seed()`,
`PYTHONHASHSEED`.

## Verification

Verification commands: see `code-py` § Verification.

## Rationalizations

| Excuse                           | Reality                                                                                  |
| -------------------------------- | ---------------------------------------------------------------------------------------- |
| "Session scope for speed"        | Mutation bugs cost more than test time. Function-scoped by default.                      |
| "Classes organize tests"         | Comment section headers organize without `self` tax or false suggestion of shared state. |
| "My mock works without autospec" | Until you rename a method. `autospec=True` catches wrong names and arg counts.           |
