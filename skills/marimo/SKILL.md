---
name: marimo-notebooks
description: Create reactive Python notebooks with automatic execution and interactive data dashboards. Use when building data analysis workflows, migrating from Jupyter, or working with reactive UIs. Covers marimo's DAG-based reactivity, UI elements (sliders, dropdowns, dataframes), polars/altair integration, and resolving circular dependencies, variable redeclaration, and mutation tracking errors.
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
|------|---------|
| Import modules | First cell: `import marimo as mo`, `import polars as pl`, `import altair as alt` |
| Create UI element | One cell: `slider = mo.ui.slider(0, 100)` |
| Access UI value | Different cell: `value = slider.value` |
| Display output | Last expression in cell (auto-displayed) |
| Stop execution | `mo.stop(condition, output=None)` |
| Layout elements | `mo.hstack([...])`, `mo.vstack([...])`, `mo.tabs({...})` |
| Run SQL | `result = mo.sql(f"""SELECT * FROM table""")` |
| Local variables | Prefix with `_`: `_temp = ...` (not accessible to other cells) |
| Run as script | `python notebook.py` (CLI execution) |
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
- **polars** for dataframes
- **altair** for visualizations

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

### SQL with DuckDB

```python
# polars DataFrame automatically available to SQL
result_df = mo.sql(f"""
    SELECT category, COUNT(*) as count
    FROM my_dataframe
    GROUP BY category
""")
```

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|--------------|-----|
| Redefining variables | `x = 1` in cell 1, `x = 2` in cell 2 | Each variable assigned in exactly one cell |
| Accessing UI in same cell | `slider = mo.ui.slider(...); print(slider.value)` | Access `.value` in a different cell |
| Mutations for reactivity | `list.append(x)` doesn't trigger updates | Create new objects: `new_list = list + [x]` |
| Circular dependencies | Cell A uses B, Cell B uses A | Reorganize to break cycle |
| Missing last expression | Output not showing | Ensure visualization/data is last expression |
| Using `global` keyword | Breaks marimo's tracking | Never use `global` |
| Callbacks for UI | `on_change=handler` | Remove callbacks, rely on reactive execution |
| Using `mo.state()` | 99% of cases don't need it, can cause bugs | Use UI element `.value` instead |

## Testing and Validation

### Linting

```bash
uv run marimo check .                # Check all notebooks
uv run marimo check --fix .          # Auto-fix safe issues
uv run marimo check --fix --unsafe-fixes .  # Fix all
```

**Key errors:**

- MB001-MB005: Breaking (syntax, multiple definitions, cycles)
- MR001: Runtime (self-import)
- MF001-MF007: Formatting (auto-fixable)

### Testing

**In-notebook reactive testing:**

```python
@app.cell
def __(inc):
    def test_increment():
        assert inc(3) == 4
    return
```

Tests auto-run when pytest installed. Test cells must contain ONLY test code.

**Command-line:**

```bash
uv run pytest notebook.py      # Run tests
uv run python notebook.py      # Validate execution
```

## API Reference

For complete API documentation, see `marimo-docs/docs/api/`:

- `api/index.md` - API overview
- `api/inputs/` - All UI components (35+ widgets)
- `api/layouts/` - Layout components (tabs, accordion, sidebar, etc.)
- `api/plotting.md` - Plotting integrations
- `api/state.md` - State management with `mo.state()`
- `api/markdown.md` - Markdown utilities

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

# Cell 2
iris = pl.read_csv("hf://datasets/scikit-learn/iris/Iris.csv")

# Cell 3
species = mo.ui.dropdown(
    options=["All"] + iris["Species"].unique().to_list(),
    value="All",
    label="Species"
)
species

# Cell 4
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

### SQL Analysis

```python
import marimo as mo
import polars as pl

weather = pl.read_csv("https://raw.githubusercontent.com/vega/vega-datasets/refs/heads/main/data/weather.csv")

seattle = mo.sql(f"""
    SELECT * FROM weather
    WHERE location = 'Seattle'
    ORDER BY date
""")
```

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "Multiple definitions" | Variable assigned in 2+ cells | Move to single cell or rename |
| "Circular dependency" | Cell cycle in DAG | Break cycle by extracting shared logic |
| UI value is None | Accessing `.value` in same cell as definition | Move access to different cell |
| Mutation doesn't update | Changed object in-place | Create new object instead |
| Cell doesn't re-run | Using local variable `_var` | Remove `_` prefix to make global |

**After changes, always run:** `uv run marimo check --fix notebook.py`
