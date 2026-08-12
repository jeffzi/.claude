---
name: code-marimo
description: >
  Use when creating reactive Python notebooks, building
  marimo data analysis dashboards, migrating from Jupyter,
  or working with marimo files (.py notebooks). Also use
  when encountering marimo errors like "multiple
  definitions", "circular dependency", or "variable
  redeclaration". Not for standard Python scripts — use
  code-py alone. Not for Shiny apps — use code-shiny.
  Not for notebooks needing side effects with manual
  execution order, variable redeclaration across cells,
  or implicit state.
user-invocable: false
---

# Marimo Reactive Notebooks

**Load `Skill(code-py)` first if not already loaded** — it carries the general Python standards this
skill builds on; this skill adds marimo-specific reactive notebook rules.

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
| Load CSV/Parquet  | SQL: `SELECT * FROM 'data.csv'` or `SELECT * FROM 'data.parquet'`                |
| Verify / test     | See **Testing and Validation** below                                             |

## Core Concepts

### Reactivity and the DAG

- Cells execute automatically when their dependencies change
- No manual "Run All" needed - changes propagate automatically
- Dependency graph prevents circular references
- UI elements trigger re-execution without explicit callbacks — every element exposes `.value`

### Variable Scoping

- **Global variables:** Declared once, accessed by any cell
- **Local variables:** Prefix with `_` only when you want cell-local scope — other cells cannot see
  or react to `_var`. When another cell must react to a value, drop the prefix and make it global.
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
- **polars** for simple operations (filtering, unique values) or when SQL can't express it (complex
  window functions, custom UDFs, operations needing Python libraries like scipy)
- **altair** for visualizations

**SQL-first principle:** DuckDB's query planner optimizes SQL, and results chain efficiently with
the `native` output type (set it in the app config).

## Runtime Modes

- **Automatic (default):** cells run automatically when dependencies change.
- **Lazy:** cells are marked stale instead of running; run manually with the Run button.

For expensive notebooks, configure lazy mode or use `mo.stop()` to prevent expensive cells from
running until ready.

## Common Patterns

### Avoiding Mutations

```python
# BAD: mutation won't trigger reactivity
original_list.append(item)

# GOOD: create new object
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

## Pitfalls

| Issue                              | Symptom/Error                  | Fix                                                                       |
| ---------------------------------- | ------------------------------ | ------------------------------------------------------------------------- |
| Variable in 2+ cells               | "Multiple definitions" error   | Assign each variable in exactly one cell                                  |
| Cell A uses B, B uses A            | "Circular dependency" error    | Break cycle by extracting shared logic                                    |
| Access `.value` in same cell as UI | UI value is None               | Move `.value` access to different cell                                    |
| Mutating objects in-place          | Changes don't trigger re-run   | Create new objects: `new_list = list + [x]`                               |
| Expected a cell to react to `_var` | Cell doesn't re-run on changes | `_` is cell-local by design — drop the prefix when other cells must react |
| Output not showing                 | Missing last expression        | Ensure visualization/data is last expression                              |
| Using `global` keyword             | Breaks marimo's tracking       | Never use `global`                                                        |
| Using `on_change=handler`          | Callbacks unnecessary          | Remove callbacks, rely on reactive execution                              |
| Using `mo.state()`                 | Can cause bugs, rarely needed  | Use UI element `.value` instead                                           |
| Naming dataframes `*_df`           | Redundant, clutters code       | Use descriptive names: `weather`, `filtered`                              |

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

Directory-wide variants: `uv run marimo check .` (check only), `--fix .` (auto-fix safe issues),
`--fix --unsafe-fixes .` (fix all). **Error codes:** MB001-MB005 (breaking), MR001 (runtime),
MF001-MF007 (formatting, auto-fixable).

### Testing

```python
@app.cell
def test_helpers(increment):
    def test_increment():
        assert increment(3) == 4
    return
```

Tests auto-run when pytest installed. Run manually: `uv run pytest notebook.py`

## API Reference

For complete API documentation, see [docs.marimo.io](https://docs.marimo.io/):

- [UI Components](https://docs.marimo.io/api/inputs/) - 35+ widgets
- [Layouts](https://docs.marimo.io/api/layouts/) - tabs, accordion, sidebar, etc.
- [Plotting](https://docs.marimo.io/api/plotting/) - Plotting integrations
- [Markdown](https://docs.marimo.io/api/markdown/) - Markdown utilities

## Examples

Extended examples — interactive data filter, data explorer, SQL-first analysis — live in
`references/examples.md`.
