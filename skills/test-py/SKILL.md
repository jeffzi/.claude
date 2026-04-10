---
name: test-py
description: >
  Use when writing Python tests with pytest. Apply for
  fixtures, mocking, parametrization, property-based
  testing, flaky tests, test isolation issues, data
  validation, AssertionError debugging, or any
  test_*.py files.
paths: "**/test_*.py, **/*_test.py, **/tests/**/*.py, **/conftest.py"
user-invocable: false
model: sonnet
effort: medium
---

# Python Testing with pytest

**This skill extends `Skill(test-core)`.** Universal principles (AAA, behavior-vs-implementation,
merge/redundancy, parametrize-over-loops, mocking anti-patterns) live in `test-core`. This file adds
pytest-specific syntax, fixtures, plugins, and pitfalls.

**Also apply:** `code-py` rules. Exception: test functions don't need `-> None` annotations.

## Domain Skill Detection

When reviewing or writing test files, check imports for domain-specific libraries. If detected, load
the corresponding skill for library-specific testing patterns:

| Import pattern                                 | Skill to load |
| ---------------------------------------------- | ------------- |
| `import polars` / `from polars.testing import` | `test-polars` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Mandatory Rules

### 1. Test Names Use the Full `test_<function>_when_<condition>_does_<expected>` Form

Don't abbreviate. `test_parse_rejects_empty` is better than `test_parse_1`, and
`test_create_user_when_email_taken_raises` is better than `test_create_user_dup`.

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
# =============================================================================
# move_object
# =============================================================================

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

### 5. Parametrize with `@pytest.mark.parametrize`

`test-core` § 6 says: parametrize whenever the same assertion runs against varying inputs. In
pytest:

```python
@pytest.mark.parametrize("a,b,expected", [
    (1, 2, 3),
    pytest.param(0, 0, 0, id="zeros"),
    pytest.param(-1, 1, 0, id="opposite-signs"),
])
def test_add(a, b, expected):
    assert add(a, b) == expected
```

Use `pytest.param(..., id="...")` to name non-obvious cases.

## Quick Reference

### Fixture Scopes

| Scope    | Use Case            | Watch Out            |
| -------- | ------------------- | -------------------- |
| function | Default, isolated   | None                 |
| class    | Shared setup        | Mutation leaks       |
| module   | Expensive resources | Cross-test pollution |
| session  | One-time setup      | Never mutate         |

### Mock This, Not That (Python boundaries)

| Mock                 | Don't mock           |
| -------------------- | -------------------- |
| HTTP clients         | Business logic       |
| Database connections | Internal functions   |
| File I/O             | Data transformations |
| External APIs        | Your own modules     |

## Pitfalls

| Never                                        | Always                                                              |
| -------------------------------------------- | ------------------------------------------------------------------- |
| `mocker.patch("mod.Class")` without autospec | `autospec=True` — catches wrong method names/args                   |
| Session-scoped mutable fixtures              | Function-scoped or copy data                                        |
| `assert x == True`                           | `assert x` or `assert x is True`                                    |
| Bare `except` in tests                       | Let exceptions propagate                                            |
| Interdependent tests                         | Each test sets up own context                                       |
| Hardcoded paths                              | Use `tmp_path` fixture                                              |
| Import boto3 before moto mock                | Import modules AFTER `@mock_aws` is active                          |
| Classes as section headers                   | Comment section headers; classes only for shared `autouse` fixtures |

## Fixture Best Practices

- Use `yield` for setup/teardown (code after yield runs even if test fails)
- `autouse=True` sparingly — only for global concerns
- `conftest.py` for shared fixtures; factory fixtures for variations

## Data Testing Patterns

| Tool                              | Use For                                                                |
| --------------------------------- | ---------------------------------------------------------------------- |
| `hypothesis`                      | Property-based testing — prefer over hardcoded data                    |
| `pandera`                         | DataFrame schema validation                                            |
| `dirty-equals`                    | Flexible assertions (`IsDatetime`, `IsUUID`, `IsPartialDict`)          |
| `pytest.approx()`                 | Float comparisons with tolerance                                       |
| `pd.testing.assert_frame_equal()` | DataFrame equality                                                     |
| `time-machine`                    | Mock datetime/time                                                     |
| `pytest-asyncio`                  | Async test support                                                     |
| `moto`                            | AWS mocking                                                            |
| `responses`                       | HTTP mocking                                                           |
| `polyfactory`                     | Generate pydantic/dataclass instances (only for complex nested models) |

**Hardcoded data only for**: realistic inputs from production (e.g., actual JSON events, real API
responses).

**Seeding**: Set ALL sources — `random.seed()`, `np.random.seed()`, `torch.manual_seed()`,
`PYTHONHASHSEED`.

## Verification

**MANDATORY before completing any task:**

```bash
pytest                   # Run test suite
ruff check .             # Lint check
```

**Task is NOT complete until all pass.**

## Rationalizations

| Excuse                           | Reality                                                                                  |
| -------------------------------- | ---------------------------------------------------------------------------------------- |
| "Session scope for speed"        | Mutation bugs cost more than test time. Function-scoped by default.                      |
| "Classes organize tests"         | Comment section headers organize without `self` tax or false suggestion of shared state. |
| "My mock works without autospec" | Until you rename a method. `autospec=True` catches wrong names and arg counts.           |
