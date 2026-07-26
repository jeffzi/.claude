---
name: code-shiny
description: >
  Use when building Shiny for Python apps, writing reactive logic, wiring up inputs
  and outputs, or encountering errors like "object of type NoneType has no len()",
  infinite reactive loops, or outputs that never update. Also use when choosing
  between Express and Core mode, handling long-running operations, or managing
  session cleanup. Not for Shinylive static-only
  deploys or Jupyter-style notebooks.
user-invocable: false
---

# Shiny for Python

**This skill extends `Skill(code-py)`.** `code-py` is the base for general Python standards; this
skill adds Shiny-specific reactive patterns on top.

**Core principle:** Reactivity is a graph, not a sequence. Every output and effect re-executes when
its reactive inputs change — understanding what is and isn't reactive is the entire skill.

## Overview

Shiny for Python is a web framework where UIs are declared once and outputs re-execute automatically
when their reactive dependencies change. It supports two authoring modes: **Express** (top-level
script, per-session execution) and **Core** (explicit `app_ui` / `server` functions with full
control over structure).

## When to Use

Use when:

- Building interactive data apps and dashboards in Python
- Adding reactive UI to existing data analysis workflows
- Need server-side rendering with WebSocket communication (vs. Shinylive for static)
- Working with `.py` files that `from shiny import` or `from shiny.express import`

Don't use when:

- Building static sites (use Shinylive / WebAssembly instead)
- Need purely client-side interactivity (consider Observable or Streamlit)
- Mixing Jupyter-style cell execution (use Marimo instead)

## Quick Reference

| Task                    | Pattern                                                         |
| ----------------------- | --------------------------------------------------------------- |
| Reactive state          | `count = reactive.value(0)` — always initialize                 |
| Cached computation      | `@reactive.calc` — recomputes only when inputs change           |
| Side effect             | `@reactive.effect` — runs on reactive change, no return value   |
| Render to UI            | `@render.text`, `@render.plot`, `@render.data_frame`            |
| Read reactive value     | `count.get()` inside reactive context                           |
| Set reactive value      | `count.set(new_val)`                                            |
| Guard against falsy     | `req(input.x())` — stops silently on falsy, None, empty         |
| Read without dependency | `with reactive.isolate(): ...`                                  |
| Trigger only on event   | `@reactive.event(input.button)`                                 |
| Non-blocking task       | `extended_task` — the only correct pattern for long ops         |
| Poll external source    | `reactive.poll(fn, interval_secs)`                              |
| Session cleanup         | `session.on_ended(cleanup_fn)`                                  |
| App-level cleanup       | `@app.on_shutdown`                                              |
| Module namespace        | `module_ui(id)` + `@module.server` decorator                    |
| Update input widget     | `ui.update_select(id, choices=...)` — cheaper than re-rendering |

## Core Concepts

### The Reactive Graph

Four primitives form the graph:

- **`reactive.value`** — source node. Holds state, notifies dependents on `.set()`.
- **`reactive.calc`** — derived node. Caches result, recomputes only when inputs change.
- **`reactive.effect`** — sink. Runs side effects when inputs change, returns nothing.
- **`render.*`** — sink. Like `effect`, but sends output to the UI.

```text
reactive.value  ──>  reactive.calc  ──>  render.*
                          │
                          └──>  reactive.effect
```

### Express vs Core

| Express                               | Core                                |
| ------------------------------------- | ----------------------------------- |
| Script top-level = UI                 | Explicit `app_ui` + `server`        |
| Re-executes entire module per session | Module-level runs once at startup   |
| App-scoped mutable state = bug        | App-scoped mutable state = safe     |
| Quick apps and prototypes             | Modules, complex layout, production |

### Mutable Objects and reactive.value Lifecycle

- **Always initialize:** `reactive.value(None)` or a sentinel. Uninitialized `.get()` raises
  `SilentException`.
- **Never mutate in-place:** `val.get().append(x)` is invisible to the graph. Always create a new
  object and call `.set()`.
- **Reading `.get()` inside a reactive context creates a dependency** — the enclosing `calc`,
  `effect`, or `render` will re-execute when the value changes.

### Decorator Ordering

When stacking decorators, the outermost decorator runs first:

```python
# Correct order: @render outermost, @reactive.event below it
@render.text
@reactive.event(input.button)
def result():
    return "Clicked"
```

Reversing the order silently breaks the binding.

## App Modes

**Express:** Write UI and server logic together at module top-level. Re-executes the entire module
per session — do not place database connections, loaded models, or any shared state at module scope;
they will be recreated per user. Use for simple apps and prototypes.

**Core:** Separate `app_ui` (called once) and `server` (called per session). Module-level code runs
once at startup and is shared across all sessions — safe for connection pools and loaded models, but
never for mutable per-user state.

## Common Patterns

### Mutable Objects in reactive.value

```python
# ❌ Mutating in-place: change is invisible to reactive graph
items = reactive.value([])
items.get().append("new")  # graph never sees this

# ✅ Replace the whole value
items = reactive.value([])
items.set(items.get() + ["new"])
```

### Always Initialize reactive.value

```python
# ❌ Uninitialized: accessing .get() raises SilentException before first .set()
selected = reactive.value()

# ✅ Initialize with None or sentinel
selected = reactive.value(None)
```

### Long-Running Operations

```python
# ❌ async def does NOT unblock the server — WSGI is single-threaded
@render.text
async def slow_output():
    result = await asyncio.sleep(5)  # blocks everyone
    return str(result)

# ✅ extended_task moves work to a thread pool
@reactive.extended_task
async def slow_task(x: int) -> str:
    await asyncio.sleep(5)
    return str(x)

@render.text
def result():
    return slow_task.result()
```

### req() Falsy Trap

```python
# ❌ req(False) always stops — constant false, not a condition
@render.text
def output():
    req(input.x() is not None)  # intended guard
    req(False)  # BUG: this always cancels

# ✅ req() on the actual condition — but beware: 0 and "" are also falsy
@render.text
def output():
    req(input.x())  # stops if x is None, 0, "", [], False
    return f"Value: {input.x()}"

# ✅ None-only guard when 0 or "" are valid
@render.text
def output():
    req(input.x() is not None)
    return f"Value: {input.x()}"
```

### reactive.event vs Manual Dependency

```python
# ❌ Using reactive.effect with manual dependency — fragile, order-sensitive
@reactive.effect
def update():
    _ = input.button()  # explicit read to create dependency
    do_work()

# ✅ reactive.event makes the trigger explicit and ignores None by default
@reactive.effect
@reactive.event(input.button)
def update():
    do_work()
```

### Session Cleanup

```python
# ❌ Resource leak — db connection never closed when user disconnects
conn = database.connect()

@render.data_frame
def table():
    return conn.query("SELECT * FROM data")

# ✅ Register cleanup on session end
conn = database.connect()
session.on_ended(lambda: conn.close())
```

### ui.update_* vs render.ui

```python
# ❌ Re-renders entire widget DOM on every input change
@render.ui
def choices():
    return ui.input_select("x", "X:", choices=get_choices(input.filter()))

# ✅ Update only the choices, preserve widget state
@reactive.effect
@reactive.event(input.filter)
def sync_choices():
    ui.update_select("x", choices=get_choices(input.filter()))
```

## Pitfalls

| Issue                                       | Symptom/Error                                  | Fix                                                       |
| ------------------------------------------- | ---------------------------------------------- | --------------------------------------------------------- |
| `reactive.value()` uninitialized            | `SilentException` before first `.set()`        | Always initialize: `reactive.value(None)`                 |
| Mutating `.get()` result in-place           | Output never updates                           | Replace value: `val.set(val.get() + [item])`              |
| `async def` output for long ops             | Server blocks all sessions                     | Use `@reactive.extended_task`                             |
| `@reactive.event` before `@render.*`        | Decorator order error / silent no-op           | Put `@render.*` outermost, `@reactive.event` below it     |
| `req(x)` where x is `0` or `""`             | Output silently cancels on valid falsy values  | Use `req(x is not None)` for None-only guard              |
| `reactive.event(ignore_none=False)` omitted | Effect fires on startup with None inputs       | Default `ignore_none=True` is usually correct             |
| `reactive.isolate()` missing                | Infinite reactive loop                         | Wrap reads that should not create dependencies            |
| Module-level mutable state in Express       | State shared across sessions / data corruption | Move mutable state inside server or use `reactive.value`  |
| DB connection in Express module scope       | New connection per user, pool exhausted        | Use `session.on_ended` + create connections inside server |
| `render.ui` for widget updates              | Full DOM re-render, lost focus/scroll state    | Use `ui.update_*` functions                               |
| `SafeException` not used                    | Full traceback shown to end user               | `raise SafeException("message")` for expected errors      |

## Rationalizations That Mean You're About to Fail

| Excuse                                                             | Reality                                                                               |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| "I'll just use `async def` for the slow part"                      | Async doesn't unblock the server. Use `extended_task`.                                |
| "reactive.value doesn't need initialization, I set it immediately" | Between startup and first set, `.get()` raises SilentException. Always initialize.    |
| "I can mutate the list from `.get()` directly"                     | In-place mutation is invisible to the reactive graph. Use `.set()`.                   |
| "render.ui is fine, it's just a dropdown"                          | `render.ui` re-renders the whole widget, losing state. Use `ui.update_select`.        |
| "I don't need cleanup, Python GC handles it"                       | Session-scoped resources (DB connections, file handles) need `session.on_ended`.      |
| "The module runs once, so this shared dict is safe"                | In Express mode, the module re-runs per session. Mutable module-level state corrupts. |
| "req() will handle None and empty string"                          | `req("")` also stops on empty string — use `req(x is not None)` when empty is valid.  |

## Testing and Validation

**MANDATORY before completing any task:**

```bash
uv run shiny run <app.py> --port 0  # Smoke test: start server, see below
uv run pytest                        # Unit tests
uv run playwright install            # First time only — installs browser
uv run pytest --headed               # E2E tests with browser UI (debug)
```

**Task is NOT complete until all pass.** Smoke test: run in background, wait for
`Application startup complete` in stdout (= success) or a traceback/exit (= failure), then kill the
server. Tests alone miss import errors, broken templates, and runtime init failures.

### Unit Testing (Extract Business Logic)

Test pure Python functions extracted from reactive callbacks — do not test Shiny wiring directly.

```python
# Extract and test pure logic
def filter_data(df: pd.DataFrame, threshold: float) -> pd.DataFrame:
    return df[df["value"] > threshold]

def test_filter_data_excludes_values_below_threshold():
    df = pd.DataFrame({"value": [1, 5, 10]})
    result = filter_data(df, threshold=4)
    assert list(result["value"]) == [5, 10]
```

### E2E Testing with Playwright

```python
from playwright.sync_api import Page
from shiny.testing import create_app_fixture

app = create_app_fixture("app.py")

def test_filter_updates_table(page: Page, app):
    page.goto(app.url)
    page.locator("#threshold").fill("4")
    page.locator("#apply").click()
    assert page.locator("#table tbody tr").count() == 2
```

## UI Elements

**Core inputs:**

- `ui.input_text(id, label)` — text input
- `ui.input_numeric(id, label, value)` — numeric input
- `ui.input_select(id, label, choices)` — dropdown
- `ui.input_slider(id, label, min, max, value)` — slider
- `ui.input_checkbox(id, label)` — checkbox
- `ui.input_action_button(id, label)` — button (use with `@reactive.event`)
- `ui.input_file(id, label)` — file upload

**Outputs:**

- `@render.text` / `ui.output_text(id)` — text
- `@render.plot` / `ui.output_plot(id)` — matplotlib / plotly
- `@render.data_frame` / `ui.output_data_frame(id)` — interactive table
- `@render.ui` / `ui.output_ui(id)` — dynamic UI
- `@render.download` / `ui.download_button(id, label)` — file download

**Layout:**

- `ui.sidebar_layout(ui.sidebar(...), ...)` — sidebar
- `ui.nav_panel(title, ...)` + `ui.navset_tab(...)` — tabs
- `ui.card(...)`, `ui.card_header(...)` — card layout
- `ui.column(width, ...)`, `ui.row(...)` — Bootstrap grid

**Update functions (prefer over render.ui):**

- `ui.update_select(id, choices=...)` — update dropdown choices
- `ui.update_slider(id, value=...)` — update slider value
- `ui.update_text(id, value=...)` — update text input

For code examples, see `references/examples.md`.
