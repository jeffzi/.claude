---
name: code-marimo
description: Use when creating reactive Python notebooks, building data analysis dashboards, migrating from Jupyter, or working with marimo files (.py notebooks). Also use when encountering marimo errors like "multiple definitions", "circular dependency", or "variable redeclaration".
---

# Marimo Reactive Notebooks

## Overview

Marimo is a reactive Python notebook where cells form a directed acyclic graph (DAG) and automatically re-execute
when dependencies change. Unlike Jupyter, variables cannot be redeclared, and execution order is determined by the
dependency graph, not cell position.

**Core principle:** Write declarative, idempotent cells that react to changes instead of imperative code with manual execution.

## When to Use

Use when:

- Creating interactive data analysis dashboards
- Building reproducible data science workflows
- Migrating from Jupyter notebooks
- Need automatic reactivity without callbacks
- Working with real-time data that requires UI updates

Don't use when:

- Need notebooks with side effects and manual execution order
- Require variable redeclaration across cells
- Working with codebases that rely on implicit state

## Quick Reference

| Task | Pattern |
| ---- | ------- |
| Import modules | First cell: `import marimo as mo`, `import polars as pl`, `import altair as alt` |
| Create UI element | One cell: `slider = mo.ui.slider(0, 100)` |
| Access UI value | Different cell: `value = slider.value` |
| Display output | Last expression in cell (auto-displayed) |
| Stop execution | `mo.stop(condition, output=None)` |
| Layout elements | `mo.hstack([...])`, `mo.vstack([...])`, `mo.tabs({...})` |
| SQL cell | Create via UI or `result = mo.sql(f"""SELECT * FROM table""")` |
| SQL output type | Set to `native` in app config for best performance |
| Load CSV/Parquet | SQL: `SELECT * FROM 'data.csv'` or `SELECT * FROM 'data.parquet'` |
| Local variables | Prefix with `_`: `_temp = ...` (not accessible to other cells) |
| Run as script | `uv run notebook.py` (CLI execution) |
| Check notebook | `uv run marimo check --fix notebook.py` |
| Test notebook | `uv run pytest notebook.py` |

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
def __(dependencies):
    # Cell code here
    return (outputs,)
```

**Important:** Only modify code inside `@app.cell` functions. Marimo manages parameters and return statements.

## Default Stack

Always use unless explicitly requested otherwise:

- **uv** for package management
- **DuckDB SQL** for data loading, joins, aggregations, complex transformations (via native SQL cells)
- **polars** for simple operations (filtering, unique values) or when SQL can't express it (UDFs)
- **altair** for visualizations

**SQL-first principle:** Prefer DuckDB SQL for data loading, joins, aggregations, and complex
transformations. SQL is optimized by DuckDB's query planner and chains efficiently with `native`
output type. Use polars for simple operations where it's more readable.

## Runtime Modes

**Automatic (default):** Cells run automatically when dependencies change
**Lazy:** Cells marked as stale instead of running; run manually with Run button

For expensive notebooks, configure lazy mode or use `mo.stop()` to prevent expensive cells from running until ready.

## Common Patterns

### Basic Reactive UI

```python
# Cell 1: Imports
import marimo as mo
import polars as pl
import altair as alt

# Cell 2: Create UI
slider = mo.ui.slider(10, 100, value=50, label="Points")
slider

# Cell 3: Use UI value (auto-updates when slider changes)
data = pl.DataFrame({"x": range(slider.value)})
alt.Chart(data).mark_line().encode(x="x")
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

**SQL output type:** Set to `native` in app config for best performance (lazy DuckDB relations, efficient chaining).

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

| Issue | Symptom/Error | Fix |
| ----- | ------------- | --- |
| Variable in 2+ cells | "Multiple definitions" error | Assign each variable in exactly one cell |
| Cell A uses B, B uses A | "Circular dependency" error | Break cycle by extracting shared logic |
| Access `.value` in same cell as UI | UI value is None | Move `.value` access to different cell |
| Mutating objects in-place | Changes don't trigger re-run | Create new objects: `new_list = list + [x]` |
| Using `_var` (local variable) | Cell doesn't re-run on changes | Remove `_` prefix to make global |
| Output not showing | Missing last expression | Ensure visualization/data is last expression |
| Using `global` keyword | Breaks marimo's tracking | Never use `global` |
| Using `on_change=handler` | Callbacks unnecessary | Remove callbacks, rely on reactive execution |
| Using `mo.state()` | Can cause bugs, rarely needed | Use UI element `.value` instead |
| Naming dataframes `*_df` | Redundant, clutters code | Use descriptive names: `weather`, `filtered` |

**After fixing issues, always run:** `uv run marimo check --fix notebook.py && uv run notebook.py`

## Testing and Validation

**MANDATORY before completing any task:**

```bash
uv run marimo check --fix notebook.py  # Fix lint errors (MB001-MB005, MR001)
uv run notebook.py                      # Validate execution (runs as script)
```

**Task is NOT complete until both pass.** Never use `uv run marimo edit` or `uv run marimo run`
for verification (they open UI/server, not validation).

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
# Cell 1
import marimo as mo
import polars as pl
import altair as alt

# Cell 2: Load data with SQL
iris = mo.sql(f"""
    SELECT * FROM 'hf://datasets/scikit-learn/iris/Iris.csv'
""")

# Cell 3: Create UI (polars for simple unique extraction)
species = mo.ui.dropdown(
    options=["All"] + iris["Species"].unique().sort().to_list(),
    value="All",
    label="Species"
)
species

# Cell 4: Filter (polars is cleaner for simple filters)
filtered = iris if species.value == "All" else iris.filter(pl.col("Species") == species.value)

alt.Chart(filtered).mark_circle().encode(
    x="SepalLengthCm",
    y="SepalWidthCm",
    color="Species"
)
```

### Data Explorer

```python
import marimo as mo
import polars as pl
from vega_datasets import data

cars = pl.DataFrame(data.cars())
mo.ui.data_explorer(cars)
```

### SQL Analysis (SQL-First Pattern)

```python
# Cell 1: Imports
import marimo as mo
import altair as alt

# Cell 2: Load and filter data directly with SQL
seattle = mo.sql(f"""
    SELECT * FROM 'https://raw.githubusercontent.com/vega/vega-datasets/refs/heads/main/data/weather.csv'
    WHERE location = 'Seattle'
    ORDER BY date
""")

# Cell 3: Aggregate with SQL
monthly_avg = mo.sql(f"""
    SELECT date_trunc('month', date) as month,
           avg(temp_max) as avg_high,
           avg(temp_min) as avg_low
    FROM seattle
    GROUP BY 1
    ORDER BY 1
""")

# Cell 4: Visualize
alt.Chart(monthly_avg).mark_line().encode(x="month", y="avg_high")
```
