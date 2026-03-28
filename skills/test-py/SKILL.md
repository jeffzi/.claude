---
name: test-py
description: >
  Use when writing Python tests with pytest. Apply for
  fixtures, mocking, parametrization, property-based
  testing, flaky tests, test isolation issues, data
  validation, AssertionError debugging, or any
  test_*.py files.
---

# Python Testing with pytest

**Core principle**: Test behavior, not implementation. Every test follows Arrange-Act-Assert.

**Also apply:** `code-py` rules. Exception: test functions don't need `-> None` annotations.

**TDD phase constraints (when invoked by a TDD agent):** RED phase (tdd-red) — write tests for ONE
behavior per invocation, no horizontal slicing. GREEN phase (tdd-green) — do NOT modify test files,
fix implementation only.

## Domain Skill Detection

When reviewing or writing test files, check imports for domain-specific libraries. If detected, load
the corresponding skill for library-specific testing patterns:

| Import pattern                                 | Skill to load |
| ---------------------------------------------- | ------------- |
| `import polars` / `from polars.testing import` | `test-polars` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Mandatory Rules

### 1. Arrange-Act-Assert Structure

```python
# ✗ Mixed up
def test_user():
    assert create_user("Alice").name == "Alice"
user = User("Bob")
    assert user.is_valid()

# ✓ Clear AAA
def test_create_user_sets_name():
    name = "Alice"

    user = create_user(name)

    assert user.name == name
```

### 2. Descriptive Test Names

Format: `test_<function>_when_<condition>_does_<expected>`

### 3. Mock at Boundaries Only

```python
# ✗ Mocking internal function
mocker.patch("myapp.weather._parse_response", return_value={...})

# ✓ Mock external HTTP call
mocker.patch("myapp.weather.requests.get", return_value=FakeResponse(...))
```

### 4. Function-Scoped Fixtures by Default

Isolation over speed. Broader scopes only for truly expensive setup.

### 5. No Loops in Tests

Use `@pytest.mark.parametrize` instead—shows all cases, runs independently.

### 6. No Classes for Logical Grouping

Use comment section headers to organize tests by topic. Reserve classes only for shared `autouse`
fixtures or class-scoped setup that can't be a module-level fixture.

```python
# ✗ Class as a section header
class TestMoveObject:
    def test_move_object_updates_position(self): ...
    def test_move_object_clamps_to_bounds(self): ...

class TestDeleteObject:
    def test_delete_object_removes_from_scene(self): ...

# ✓ Comment sections + plain functions
# =============================================================================
# move_object
# =============================================================================

def test_move_object_updates_position(): ...
def test_move_object_clamps_to_bounds(): ...

# =============================================================================
# delete_object
# =============================================================================

def test_delete_object_removes_from_scene(): ...
```

### 7. MVP Tests - Minimum Tests, Maximum Coverage

```python
# ✗ Separate tests for same code path
def test_rejects_none(): ...
def test_rejects_empty(): ...

# ✓ Merge related validations
def test_rejects_invalid_input():
    with pytest.raises(ValueError): fn(None)
    with pytest.raises(ValueError): fn("")
```

| Merge when                          | Keep separate when    |
| ----------------------------------- | --------------------- |
| Same code path, different inputs    | Different code paths  |
| Related edge cases (None, empty, 0) | Complex setup differs |
| Same behavior across APIs           | Tests need isolation  |

## Quick Reference

### Fixture Scopes

| Scope    | Use Case            | Watch Out            |
| -------- | ------------------- | -------------------- |
| function | Default, isolated   | None                 |
| class    | Shared setup        | Mutation leaks       |
| module   | Expensive resources | Cross-test pollution |
| session  | One-time setup      | Never mutate         |

### Parametrization

```python
@pytest.mark.parametrize("a,b,expected", [
    (1, 2, 3),
    pytest.param(0, 0, 0, id="zeros"),
])
def test_add(a, b, expected):
    assert add(a, b) == expected
```

### Mock This, Not That

| ✓ Mock               | ✗ Not                |
| -------------------- | -------------------- |
| HTTP clients         | Business logic       |
| Database connections | Internal functions   |
| File I/O             | Data transformations |
| External APIs        | Your own modules     |

**Always use `autospec=True`**—catches typos in mocked method names and wrong argument counts.

## Pitfalls

| ✗ Never                         | ✓ Always                                                            |
| ------------------------------- | ------------------------------------------------------------------- |
| Mock internal functions         | Mock at system boundaries                                           |
| Session-scoped mutable fixtures | Function-scoped or copy data                                        |
| Loops in test body              | `@pytest.mark.parametrize`                                          |
| `assert x == True`              | `assert x` or `assert x is True`                                    |
| Bare `except` in tests          | Let exceptions propagate                                            |
| Interdependent tests            | Each test sets up own context                                       |
| Hardcoded paths                 | Use `tmp_path` fixture                                              |
| Over-mocking everything         | Use fakes for integration                                           |
| Import boto3 before moto mock   | Import modules AFTER `@mock_aws` is active                          |
| Classes as section headers      | Comment section headers; classes only for shared `autouse` fixtures |

## Fixture Best Practices

- Use `yield` for setup/teardown (code after yield runs even if test fails)
- `autouse=True` sparingly—only for global concerns
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

| Excuse                        | Reality                                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------- |
| "Mocking internals is faster" | You're testing implementation, not behavior.                                             |
| "Loop is cleaner"             | Parametrize shows all cases, loop stops at first failure.                                |
| "Session scope for speed"     | Mutation bugs cost more than test time.                                                  |
| "All mocks pass"              | If integration fails, mocks gave false security.                                         |
| "Classes organize tests"      | Comment section headers organize without `self` tax or false suggestion of shared state. |
