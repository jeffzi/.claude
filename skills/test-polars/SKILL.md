---
name: test-polars
description: >
  Use when writing tests for Python code that uses Polars DataFrames. Apply for assert_frame_equal
  usage, null/NaN assertion pitfalls, expression isolation testing, schema mismatches in fixtures,
  non-deterministic group_by order, float tolerance, or any test files importing polars.
---

# Testing Polars Code

**Core principle:** Test behavior, not implementation. Every test follows Arrange-Act-Assert.

**Also apply:** `test-py` rules (pytest patterns), `code-py` rules. Exception: test functions don't
need `-> None` annotations.

**TDD phase constraints (when invoked by a TDD agent):** RED phase (tdd-red) — write tests for ONE
behavior per invocation, no horizontal slicing. GREEN phase (tdd-green) — do NOT modify test files,
fix implementation only.

## Mandatory Rules

### 1. Never Wrap `assert_frame_equal` in `assert`

`assert_frame_equal` returns `None` on success and raises `AssertionError` on failure. Writing
`assert assert_frame_equal(...)` ALWAYS fails because `assert None` is falsy.

```python
# ✗ Always fails — assert_frame_equal returns None
assert assert_frame_equal(result, expected)

# ✓ Call directly — it raises on mismatch
assert_frame_equal(result, expected)
```

Same applies to `assert_series_equal`.

### 2. Always Specify `schema=` in Test Fixtures

Polars infers `[1, 2, 3]` as `Int64`, but production Parquet may be `Int32`. Omitting the schema
creates tests that pass locally but fail when production dtypes differ.

```python
# ✗ Implicit schema — type inference may not match production
df = pl.DataFrame({"id": [1, 2], "amount": [10.5, None]})

# ✓ Explicit schema — matches production dtypes
df = pl.DataFrame(
    {"id": [1, 2], "amount": [10.5, None]},
    schema={"id": pl.Int32, "amount": pl.Float64},
)
```

Define schema once and reuse across fixtures:

```python
ORDERS_SCHEMA = {"id": pl.Int32, "amount": pl.Float64, "status": pl.Utf8}

@pytest.fixture
def orders():
    return pl.DataFrame(
        {"id": [1, 2], "amount": [10.5, None], "status": ["paid", "pending"]},
        schema=ORDERS_SCHEMA,
    )
```

### 3. Use `check_row_order=False` for Non-Deterministic Output

`group_by` output order is non-deterministic. Tests that rely on row order are flaky.

```python
# ✗ Flaky — group_by order is not guaranteed
result = df.group_by("region").agg(pl.sum("sales"))
expected = pl.DataFrame({"region": ["east", "west"], "sales": [100, 200]})
assert_frame_equal(result, expected)

# ✓ Order-independent comparison
assert_frame_equal(result, expected, check_row_order=False)
```

Also applies to: `join` with `how="cross"`, `unique()`, `sample()`, and any operation documented as
having non-deterministic order.

### 4. Normalize NaN to Null Before Assertions

Polars has two distinct missing values: `null` (skipped by aggregations) and `NaN` (propagates
through aggregations). A single NaN makes `sum()`/`mean()` return NaN. `null_count()` does NOT count
NaN. `fill_null()` does NOT fill NaN.

```python
# ✗ NaN propagation makes this fail unexpectedly
df = pl.DataFrame({"val": [1.0, float("nan"), None]})
assert df.select(pl.col("val").sum()).item() == 1.0  # FAILS: returns NaN

# ✓ Normalize NaN to null at test boundaries
df_clean = df.with_columns(pl.col("val").fill_nan(None))
assert df_clean.select(pl.col("val").sum()).item() == 1.0

# ✓ Test NaN behavior explicitly when that IS the behavior under test
result = df.select(pl.col("val").is_nan())
expected = pl.Series("val", [False, True, None])
assert_series_equal(result.to_series(), expected)
```

When testing code that should handle NaN: test it explicitly. When testing code that should NOT
encounter NaN: normalize first, then assert.

### 5. Test Expressions in Isolation

The most effective Polars unit-testing pattern: test an expression against a minimal DataFrame
rather than testing an entire pipeline.

```python
# ✗ Testing the whole pipeline — hard to isolate failures
def test_revenue_pipeline():
    result = load_and_compute_revenue("orders.parquet")
    assert result.height == 42

# ✓ Test the expression in isolation with controlled data
def test_revenue_expression():
    expr = (pl.col("qty") * pl.col("price")).alias("revenue")

    df = pl.DataFrame(
        {"qty": [10, 0, None], "price": [5.0, 3.0, 7.0]},
        schema={"qty": pl.Int64, "price": pl.Float64},
    )
    result = df.select(expr)

    expected = pl.DataFrame({"revenue": [50.0, 0.0, None]}, schema={"revenue": pl.Float64})
    assert_frame_equal(result, expected)
```

Extract expressions into named variables or functions to make them testable.

### 6. Test Null Preservation Through Filters

`!=` filter silently drops null rows because `null != X` evaluates to `null`, and `.filter()` only
retains `True` rows. Tests MUST explicitly verify null row handling.

```python
# ✗ Does not verify null rows are preserved — passes with wrong behavior
def test_exclude_inactive():
    df = pl.DataFrame({"status": ["active", "inactive", "active"]})
    result = exclude_inactive(df)
    assert result.height == 2

# ✓ Includes null rows in test data, verifies they survive
def test_exclude_inactive_preserves_nulls():
    df = pl.DataFrame(
        {"status": ["active", "inactive", None, "active"]},
        schema={"status": pl.Utf8},
    )

    result = exclude_inactive(df)

    expected_statuses = {"active", None}
    actual_statuses = set(result["status"].to_list())
    assert actual_statuses == expected_statuses
    assert result.height == 3
```

**Any test for a filter operation MUST include null values in the test data.** If the function uses
`!=`, verify that null rows are either preserved (via `ne_missing`) or explicitly documented as
dropped.

### 7. Use `check_exact=False` for Float Results, Validate Cast Truncation

Float comparisons need tolerance. Also, `strict=True` cast does NOT prevent float-to-integer
truncation — `5.8` silently becomes `5`.

```python
# ✗ Floating-point precision fails exact comparison
assert_frame_equal(result, expected)  # may fail on 0.30000000000000004 vs 0.3

# ✓ Tolerance-based comparison
assert_frame_equal(result, expected, check_exact=False, rtol=1e-5)

# ✗ Trusting strict=True to catch truncation
result = df.select(pl.col("amount").cast(pl.Int32, strict=True))
# 5.8 → 5 silently, no error!

# ✓ Assert no precision loss before casting
def test_cast_rejects_non_integer_floats():
    df = pl.DataFrame({"amount": [4.0, 5.8]}, schema={"amount": pl.Float64})
    has_decimals = df.select(
        (pl.col("amount") != pl.col("amount").floor()).any()
    ).item()
    assert has_decimals  # proves 5.8 would be truncated
```

### 8. Use Property-Based Testing for Pipeline Invariants

Polars ships native Hypothesis integration via `polars.testing.parametric`. Use it to discover edge
cases deterministic fixtures miss: all-null frames, NaN injection, Int64 boundaries.

```python
from polars.testing.parametric import dataframes, column
from hypothesis import given

# ✗ Only tests the happy path with hand-picked data
def test_pipeline():
    df = pl.DataFrame({"amount": [1.0, 2.0, 3.0]})
    assert my_pipeline(df).height == 3

# ✓ Tests structural invariants across random inputs
@given(
    dataframes(
        cols=[column("amount", dtype=pl.Float64)],
        allow_null=True,
        min_size=0,
        max_size=50,
    )
)
def test_pipeline_preserves_row_count(df: pl.DataFrame):
    result = my_pipeline(df)
    assert result.height == df.height
    assert "output" in result.columns
```

Key properties to test: row count invariants, no unexpected nulls introduced, schema stability,
idempotency.

## Quick Reference

### `assert_frame_equal` Parameters

| Parameter            | Default | When to Use                                        |
| -------------------- | ------- | -------------------------------------------------- |
| `check_row_order`    | `True`  | `False` for group_by, unique, join, sample results |
| `check_column_order` | `True`  | `False` when column order is irrelevant            |
| `check_exact`        | `True`  | `False` for float comparisons                      |
| `rtol`               | `1e-5`  | Relative tolerance (requires `check_exact=False`)  |
| `atol`               | `1e-8`  | Absolute tolerance (requires `check_exact=False`)  |
| `categorical_as_str` | `False` | `True` when comparing categoricals across caches   |
| `check_dtypes`       | `True`  | `False` only when dtype mismatch is expected       |

**Do NOT wrap in `assert`** — it returns `None`.

### Null vs NaN Behavior

| Operation                  | `null`               | `NaN`               |
| -------------------------- | -------------------- | ------------------- |
| `sum()` / `mean()`         | Skipped              | Propagates (-> NaN) |
| `null_count()`             | Counted              | NOT counted         |
| `is_null()`                | `True`               | `False`             |
| `is_nan()`                 | `null`               | `True`              |
| `fill_null(0)`             | Filled               | NOT filled          |
| `fill_nan(0)`              | NOT filled           | Filled              |
| `!= X` in filter           | Dropped (-> `null`)  | Kept                |
| `sum_horizontal` (default) | Ignored (-> 0)       | Propagates (-> NaN) |
| Arithmetic `+`             | Propagates (-> null) | Propagates (-> NaN) |

**Rule of thumb:** Normalize NaN to null with `fill_nan(None)` at ingestion boundaries.

## Pitfalls

| Trap                                        | Instead                                                       |
| ------------------------------------------- | ------------------------------------------------------------- |
| `assert assert_frame_equal(...)`            | Call directly — it returns `None`                             |
| Omitting `schema=` in test DataFrames       | Always explicit — prevents type inference mismatch            |
| Row-order-dependent group_by assertions     | `check_row_order=False`                                       |
| Exact float comparison                      | `check_exact=False, rtol=1e-5`                                |
| Trusting `strict=True` prevents truncation  | Validate `col != col.floor()` before float->int cast          |
| NaN in test data without normalization      | `fill_nan(None)` at boundaries, or test NaN behavior directly |
| Filter tests without null values in data    | Always include null rows in filter test fixtures              |
| `collect_schema()` as sole schema check     | Verify critical paths against materialized sample             |
| Join without `validate=` in assertions      | Always specify `validate="m:1"` or expected cardinality       |
| `when-then-otherwise` assumed short-circuit | All branches evaluate — cast in `then()` runs on ALL rows     |
| Timezone-aware datetime cast to Date        | Converts via UTC, not local time — test both                  |

## Rationalizations

| Excuse                                          | Reality                                                          |
| ----------------------------------------------- | ---------------------------------------------------------------- |
| "Schema doesn't matter in tests"                | Inference mismatches cause false passes. Explicit schema always. |
| "Row order is deterministic on my machine"      | Non-deterministic by spec. It will break in CI.                  |
| "`assert assert_frame_equal` — extra safety"    | Returns `None`. You're asserting `None` is truthy. It never is.  |
| "NaN won't appear in my data"                   | CSV reads, Pandas conversions, division by zero all produce NaN. |
| "Float comparison is close enough without rtol" | `0.1 + 0.2 != 0.3`. Use tolerance.                               |
| "`strict=True` catches bad casts"               | It catches overflow, not truncation. 5.8 -> 5 silently.          |
| "Filter tests don't need null rows"             | `!=` silently drops nulls. If you don't test it, you don't know. |
| "Property-based tests are overkill"             | They find all-null frames, NaN injection, overflow — you won't.  |
