---
name: code-marimo
description: >
  Use when creating reactive Python notebooks, building
  data analysis dashboards, migrating from Jupyter, or
  working with marimo files (.py notebooks). Also use
  when encountering marimo errors like "multiple
  definitions", "circular dependency", or "variable
  redeclaration". Load alongside code-py for Python
  standards. Not for standard Python scripts — use
  code-py alone. Not for notebooks needing side
  effects with manual execution order, variable
  redeclaration across cells, or implicit state.
---

# Marimo Reactive Notebooks

## Overview

Marimo is a reactive Python notebook where cells form a DAG and auto-re-execute when dependencies
change — variables cannot be redeclared and execution order follows the dependency graph.

**Core principle:** Write declarative, idempotent cells that react to changes instead of imperative
code with manual execution.

## Quick Reference

| Task              | Pattern                                                                          |
| ----------------- | -------------------------------------------------------------------------------- |
| Import modules    | First cell: `import marimo as mo`, `import polars as pl`, `import altair as alt` |
| Create UI element | One cell: `slider = mo.ui.slider(0, 100)`                                        |
| Access UI value   | Different cell: `value = slider.value`                                           |
| Display output    | Last expression in cell (auto-displayed)                                         |
| Stop execution    | `mo.stop(condition, output=None)`                                                |
| Layout elements   | `mo.hstack([...])`, `mo.vstack([...])`, `mo.tabs({...})`                         |
| SQL cell          | Create via UI or `result = mo.sql(f"""SELECT * FROM table""")`                   |
| SQL output type   | Set to `native` in app config for best performance                               |
| Load CSV/Parquet  | SQL: `SELECT * FROM 'data.csv'` or `SELECT * FROM 'data.parquet'`                |
| Local variables   | Prefix with `_`: `_temp = ...` (not accessible to other cells)                   |
| Run as script     | `uv run notebook.py` (CLI execution)                                             |
| Check notebook    | `uv run marimo check --fix notebook.py`                                          |
| Test notebook     | `uv run pytest notebook.py`                                                      |

## Core Concepts

### Reactivity and the DAG

- Cells execute automatically when their dependencies change
- No manual "Run All" needed - changes propagate automatically
- Dependency graph prevents circular references
- UI elements trigger re-execution without explicit callbacks

### Variable Scoping

- **Global variables:** Declared once, accessed by any cell
- **Local variables:** Prefixed with `_`, scoped to single cell
- **Cannot redeclare:** Each variable name can only be assigned in one cell
- **Mutations not tracked:** Create new objects instead of mutating
- **Module auto-reload:** Import helper modules; marimo reloads them automatically on change

### Cell Structure

```python
@app.cell
def cell_name(dependencies):
    # Cell code here
    return (outputs,)
```

**Important:**

- **Always name cells** - Use descriptive function names (e.g., `imports`, `constants`, `load_data`,
  `filter_ui`)
- Only modify code inside `@app.cell` functions. Marimo manages parameters and return statements.

### Notebook Organization

Every notebook must follow this structure:

1. **First cell: `imports`** - All imports in a single cell at the top
2. **Second cell: `constants`** - Configuration values, URLs, thresholds, etc.
3. **Third cell: `defaults`** - Default values for UI elements (only if notebook has UI)
4. **Remaining cells** - Data loading, transformations, UI elements, visualizations

```python
@app.cell
def imports():
    import marimo as mo
    import polars as pl
    import altair as alt
    return mo, pl, alt

@app.cell
def constants():
    DATA_URL = "https://example.com/data.csv"
    MAX_ROWS = 1000
    return DATA_URL, MAX_ROWS

@app.cell
def defaults():
    # Only include this cell if notebook has UI elements
    DEFAULT_SLIDER_VALUE = 50
    DEFAULT_SPECIES = "All"
    return DEFAULT_SLIDER_VALUE, DEFAULT_SPECIES
```

## Default Stack

Always use unless explicitly requested otherwise:

- **uv** for package management
- **DuckDB SQL** for data loading, joins, aggregations, complex transformations (via native SQL
  cells)
- **polars** for simple operations (filtering, unique values) or when SQL can't express it (UDFs)
- **altair** for visualizations

**SQL-first principle:** Prefer DuckDB SQL for data loading, joins, aggregations, and complex
transformations. SQL is optimized by DuckDB's query planner and chains efficiently with `native`
output type. Use polars for simple operations where it's more readable.

## Runtime Modes

**Automatic (default):** Cells run automatically when dependencies change **Lazy:** Cells marked as
stale instead of running; run manually with Run button

For expensive notebooks, configure lazy mode or use `mo.stop()` to prevent expensive cells from
running until ready.

## Common Patterns

### Basic Reactive UI

```python
@app.cell
def imports():
    import marimo as mo
    import polars as pl
    import altair as alt
    return mo, pl, alt

@app.cell
def constants():
    MIN_POINTS = 10
    MAX_POINTS = 100
    return MIN_POINTS, MAX_POINTS

@app.cell
def defaults():
    DEFAULT_POINTS = 50
    return (DEFAULT_POINTS,)

@app.cell
def slider_ui(mo, MIN_POINTS, MAX_POINTS, DEFAULT_POINTS):
    slider = mo.ui.slider(MIN_POINTS, MAX_POINTS, value=DEFAULT_POINTS, label="Points")
    slider
    return (slider,)

@app.cell
def chart(pl, alt, slider):
    # Auto-updates when slider changes
    data = pl.DataFrame({"x": range(slider.value)})
    alt.Chart(data).mark_line().encode(x="x")
    return (data,)
```

### Avoiding Mutations

```python
# ❌ Bad: Mutation won't trigger reactivity
original_list.append(item)

# ✅ Good: Create new object
extended_list = original_list + [item]
```

### Conditional Execution

```python
# Stop expensive cells conditionally
mo.stop(not data_loaded, mo.md("Load data first"))

# Rest of cell only runs if data_loaded is True
expensive_computation(data)
```

### SQL Cells (Preferred for Data Operations)

**Creating SQL cells:**

- Right-click add cell button → "SQL cell"
- Convert empty cell to SQL via cell context menu
- Click SQL button at notebook bottom

**SQL output type:** Set to `native` in app config for best performance (lazy DuckDB relations,
efficient chaining).

```python
# Load data directly with SQL (no polars read needed)
weather = mo.sql(f"""
    SELECT * FROM 'weather.csv'
    WHERE location = 'Seattle'
""")

# Chain SQL cells - reference previous results by variable name
monthly = mo.sql(f"""
    SELECT date_trunc('month', date) as month, avg(temp) as avg_temp
    FROM weather
    GROUP BY 1
""")
```

**When to use polars instead:**

- Simple operations that are more readable (e.g., `.unique()`, `.filter()`, column selection)
- Complex window functions not expressible in SQL
- Custom Python UDFs
- Operations requiring Python libraries (e.g., scipy for statistics)

## Pitfalls

| Issue                              | Symptom/Error                  | Fix                                          |
| ---------------------------------- | ------------------------------ | -------------------------------------------- |
| Variable in 2+ cells               | "Multiple definitions" error   | Assign each variable in exactly one cell     |
| Cell A uses B, B uses A            | "Circular dependency" error    | Break cycle by extracting shared logic       |
| Access `.value` in same cell as UI | UI value is None               | Move `.value` access to different cell       |
| Mutating objects in-place          | Changes don't trigger re-run   | Create new objects: `new_list = list + [x]`  |
| Using `_var` (local variable)      | Cell doesn't re-run on changes | Remove `_` prefix to make global             |
| Output not showing                 | Missing last expression        | Ensure visualization/data is last expression |
| Using `global` keyword             | Breaks marimo's tracking       | Never use `global`                           |
| Using `on_change=handler`          | Callbacks unnecessary          | Remove callbacks, rely on reactive execution |
| Using `mo.state()`                 | Can cause bugs, rarely needed  | Use UI element `.value` instead              |
| Naming dataframes `*_df`           | Redundant, clutters code       | Use descriptive names: `weather`, `filtered` |

**After fixing issues, always run:** `uv run marimo check --fix notebook.py && uv run notebook.py`

## Rationalizations That Mean You're About to Fail

| Excuse                                         | Reality                                                     |
| ---------------------------------------------- | ----------------------------------------------------------- |
| "I'll just use `global` for this one variable" | `global` breaks marimo's tracking. Use cell returns.        |
| "`on_change` callbacks are more explicit"      | Callbacks are unnecessary — reactivity handles it.          |
| "`mo.state()` gives me more control"           | `mo.state()` is a footgun. Use UI element `.value` instead. |
| "I can redeclare this in another cell"         | One cell per variable. Extract shared logic to a helper.    |
| "Mutating this list in place is fine"          | Mutations don't trigger reactivity. Create new objects.     |
| "Cell names don't matter"                      | Unnamed cells make debugging and navigation harder.         |
| "I'll skip the `defaults` cell for now"        | Default values prevent stale UI state across restarts.      |

## Testing and Validation

**MANDATORY before completing any task:**

```bash
uv run marimo check --fix notebook.py  # Fix lint errors (MB001-MB005, MR001)
uv run notebook.py                      # Validate execution (runs as script)
```

**Task is NOT complete until both pass.** Never use `uv run marimo edit` or `uv run marimo run` for
verification (they open UI/server, not validation).

### Linting

```bash
uv run marimo check .                        # Check all notebooks
uv run marimo check --fix .                  # Auto-fix safe issues
uv run marimo check --fix --unsafe-fixes .   # Fix all
```

**Error codes:** MB001-MB005 (breaking), MR001 (runtime), MF001-MF007 (formatting, auto-fixable)

### Testing

```python
@app.cell
def __(inc):
    def test_increment():
        assert inc(3) == 4
    return
```

Tests auto-run when pytest installed. Run manually: `uv run pytest notebook.py`

## API Reference

For complete API documentation, see [docs.marimo.io](https://docs.marimo.io/):

- [UI Components](https://docs.marimo.io/api/inputs/) - 35+ widgets
- [Layouts](https://docs.marimo.io/api/layouts/) - tabs, accordion, sidebar, etc.
- [Plotting](https://docs.marimo.io/api/plotting/) - Plotting integrations
- [Markdown](https://docs.marimo.io/api/markdown/) - Markdown utilities

## UI Elements

**Core inputs:**

- `mo.ui.slider(start, stop, value, label)` - Numeric slider
- `mo.ui.dropdown(options, value, label)` - Dropdown select
- `mo.ui.text(value, label)` - Text input
- `mo.ui.checkbox(label, value)` - Checkbox
- `mo.ui.button(value, kind)` - Button
- `mo.ui.run_button(label, tooltip)` - Run button (doesn't auto-execute)

**Data inputs:**

- `mo.ui.dataframe(df)` - Interactive dataframe viewer
- `mo.ui.data_explorer(df)` - Data exploration interface
- `mo.ui.table(data, sortable, filterable)` - Interactive table
- `mo.ui.file(label, multiple)` - File upload

**Layouts:**

- `mo.hstack([...])` - Horizontal stack
- `mo.vstack([...])` - Vertical stack
- `mo.tabs({key: element, ...})` - Tabbed interface

**Access values:** All UI elements expose `.value` attribute

## Examples

### Interactive Data Filter

```python
@app.cell
def imports():
    import marimo as mo
    import polars as pl
    import altair as alt
    return mo, pl, alt

@app.cell
def constants():
    IRIS_URL = "hf://datasets/scikit-learn/iris/Iris.csv"
    return (IRIS_URL,)

@app.cell
def defaults():
    DEFAULT_SPECIES = "All"
    return (DEFAULT_SPECIES,)

@app.cell
def load_data(mo, IRIS_URL):
    iris = mo.sql(f"""
        SELECT * FROM '{IRIS_URL}'
    """)
    return (iris,)

@app.cell
def species_dropdown(mo, iris, DEFAULT_SPECIES):
    species = mo.ui.dropdown(
        options=["All"] + iris["Species"].unique().sort().to_list(),
        value=DEFAULT_SPECIES,
        label="Species"
    )
    species
    return (species,)

@app.cell
def scatter_plot(pl, alt, iris, species):
    filtered = iris if species.value == "All" else iris.filter(pl.col("Species") == species.value)
    alt.Chart(filtered).mark_circle().encode(
        x="SepalLengthCm",
        y="SepalWidthCm",
        color="Species"
    )
    return (filtered,)
```

### Data Explorer

```python
@app.cell
def imports():
    import marimo as mo
    import polars as pl
    from vega_datasets import data
    return mo, pl, data

@app.cell
def explore_cars(mo, pl, data):
    cars = pl.DataFrame(data.cars())
    mo.ui.data_explorer(cars)
    return (cars,)
```

### SQL Analysis (SQL-First Pattern)

```python
@app.cell
def imports():
    import marimo as mo
    import altair as alt
    return mo, alt

@app.cell
def constants():
    WEATHER_URL = "https://raw.githubusercontent.com/vega/vega-datasets/refs/heads/main/data/weather.csv"
    LOCATION = "Seattle"
    return WEATHER_URL, LOCATION

@app.cell
def load_weather(mo, WEATHER_URL, LOCATION):
    seattle = mo.sql(f"""
        SELECT * FROM '{WEATHER_URL}'
        WHERE location = '{LOCATION}'
        ORDER BY date
    """)
    return (seattle,)

@app.cell
def aggregate_monthly(mo, seattle):
    monthly_avg = mo.sql(f"""
        SELECT date_trunc('month', date) as month,
               avg(temp_max) as avg_high,
               avg(temp_min) as avg_low
        FROM seattle
        GROUP BY 1
        ORDER BY 1
    """)
    return (monthly_avg,)

@app.cell
def visualize(alt, monthly_avg):
    alt.Chart(monthly_avg).mark_line().encode(x="month", y="avg_high")
    return
```
