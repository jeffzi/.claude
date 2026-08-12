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

**Load `Skill(code-py)` first if it is not already active** — it carries the general Python
standards; this skill adds Shiny-specific reactive patterns on top.

**Core principle:** Reactivity is a graph, not a sequence. Every output and effect re-executes when
its reactive inputs change — understanding what is and isn't reactive is the entire skill.

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

| Task                    | Pattern                                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------------------ |
| Reactive state          | `count = reactive.value(0)` — always initialize                                                        |
| Cached computation      | `@reactive.calc` — recomputes only when inputs change                                                  |
| Side effect             | `@reactive.effect` — runs on reactive change, no return value                                          |
| Render to UI            | `@render.text`, `@render.plot`, `@render.data_frame`                                                   |
| Read reactive value     | `count.get()` inside reactive context                                                                  |
| Set reactive value      | `count.set(new_val)`                                                                                   |
| Guard against falsy     | `req(input.x())` — stops silently on `None`, `0`, `""`, `[]`; `req(x is not None)` when falsy is valid |
| Read without dependency | `with reactive.isolate(): ...`                                                                         |
| Trigger only on event   | `@reactive.event(input.button)`                                                                        |
| Non-blocking task       | `extended_task` — the only correct pattern for long ops                                                |
| Poll external source    | `reactive.poll(fn, interval_secs)`                                                                     |
| Session cleanup         | `session.on_ended(cleanup_fn)`                                                                         |
| App-level cleanup       | `@app.on_shutdown`                                                                                     |
| Module namespace        | `module_ui(id)` + `@module.server` decorator                                                           |
| Update input widget     | `ui.update_select(id, choices=...)` — cheaper than re-rendering                                        |

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

### reactive.value Lifecycle

- **Always initialize:** `reactive.value(None)` or a sentinel. Uninitialized `.get()` raises
  `SilentException`.
- **Never mutate in-place:** `val.get().append(x)` is invisible to the graph. Always create a new
  object and call `.set()`.
- **Reading `.get()` inside a reactive context creates a dependency** — the enclosing `calc`,
  `effect`, or `render` will re-execute when the value changes.
- **A `reactive.Value` is callable:** `val()` is equivalent to `val.get()`.

```python
# BAD: uninitialized — .get() raises SilentException before first .set();
#      in-place mutation — the graph never sees it
items = reactive.value()
items.get().append("new")

# GOOD: initialize, then replace the whole value
items = reactive.value([])
items.set(items.get() + ["new"])
```

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

| Express                               | Core                                |
| ------------------------------------- | ----------------------------------- |
| Script top-level = UI                 | Explicit `app_ui` + `server`        |
| Re-executes entire module per session | Module-level runs once at startup   |
| App-scoped mutable state = bug        | App-scoped mutable state = safe     |
| Quick apps and prototypes             | Modules, complex layout, production |

## Common Patterns

### Long-Running Operations

```python
# BAD: awaiting inside a render holds this session's reactive flush —
# async does not move the work anywhere (Shiny for Python is ASGI;
# the event loop keeps serving, but this session's outputs stall)
@render.text
async def slow_output():
    summary = await slow_query()  # outputs stall until this finishes
    return summary

# GOOD: extended_task runs the work as a background task
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
# BAD: cancels when min_price is 0 — a valid price
@render.text
def price_summary():
    req(input.min_price())  # stops on None, 0, "", [], False
    return f"From: {input.min_price()}"

# GOOD: None-only guard when 0 or "" are valid values
@render.text
def price_summary():
    req(input.min_price() is not None)
    return f"From: {input.min_price()}"
```

### reactive.event vs Manual Dependency

```python
# BAD: reactive.effect with manual dependency — fragile, order-sensitive
@reactive.effect
def update():
    _ = input.button()  # explicit read to create dependency
    do_work()

# GOOD: reactive.event makes the trigger explicit and ignores None by default
@reactive.effect
@reactive.event(input.button)
def update():
    do_work()
```

### Session Cleanup

```python
# BAD: resource leak — db connection never closed when user disconnects
conn = database.connect()

@render.data_frame
def table():
    return conn.query("SELECT * FROM data")

# GOOD: register cleanup on session end
conn = database.connect()
session.on_ended(lambda: conn.close())
```

### ui.update_* vs render.ui

```python
# BAD: re-renders entire widget DOM on every input change, losing focus/scroll state
@render.ui
def choices():
    return ui.input_select("x", "X:", choices=get_choices(input.filter()))

# GOOD: update only the choices, preserve widget state
@reactive.effect
@reactive.event(input.filter)
def sync_choices():
    ui.update_select("x", choices=get_choices(input.filter()))
```

`ui.update_slider(id, value=...)`, `ui.update_text(id, value=...)`, and the other `ui.update_*`
functions follow the same pattern.

## Pitfalls

Only traps without a section above:

| Issue                                   | Symptom/Error                                                    | Fix                                                                            |
| --------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `reactive.event(ignore_none=False)` set | Effect fires on startup with None inputs                         | Drop the argument — the `ignore_none=True` default suppresses the startup fire |
| `reactive.isolate()` missing            | Infinite reactive loop (an effect reads and sets the same value) | Wrap reads that should not create dependencies                                 |
| DB connection in Express module scope   | New connection per user, pool exhausted                          | Create connections inside server + `session.on_ended`                          |
| `SafeException` not used                | Full traceback shown to end user                                 | `raise SafeException("message")` for expected errors                           |

## Rationalizations That Mean You're About to Fail

| Excuse                                                             | Reality                                                                               |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| "I'll just use `async def` for the slow part"                      | An awaited render still holds the session's flush. Use `extended_task`.               |
| "reactive.value doesn't need initialization, I set it immediately" | Between startup and first set, `.get()` raises SilentException. Always initialize.    |
| "I can mutate the list from `.get()` directly"                     | In-place mutation is invisible to the reactive graph. Use `.set()`.                   |
| "render.ui is fine, it's just a dropdown"                          | `render.ui` re-renders the whole widget, losing state. Use `ui.update_select`.        |
| "I don't need cleanup, Python GC handles it"                       | Session-scoped resources (DB connections, file handles) need `session.on_ended`.      |
| "The module runs once, so this shared dict is safe"                | In Express mode, the module re-runs per session. Mutable module-level state corrupts. |
| "req() will handle None and empty string"                          | `req("")` also stops on empty string — use `req(x is not None)` when empty is valid.  |

## Testing and Validation

**MANDATORY before completing any task:**

```bash
uv run shiny run app.py --port 0 > /tmp/shiny-smoke.log 2>&1 &
SHINY_PID=$!
sleep 3 && grep -q "Application startup complete" /tmp/shiny-smoke.log \
  && echo SMOKE-OK || cat /tmp/shiny-smoke.log
kill $SHINY_PID

uv run pytest
```

**Task is NOT complete until the smoke test prints SMOKE-OK and pytest passes.** Tests alone miss
import errors, broken templates, and runtime init failures.

Prerequisite: Playwright E2E tests need a one-time `uv run playwright install`. For debugging E2E
with a visible browser, `uv run pytest --headed` (needs a display — not part of the gate).

### Unit Testing (Extract Business Logic)

Test pure Python functions extracted from reactive callbacks — do not test Shiny wiring directly.

### E2E Testing with Playwright

```python
from playwright.sync_api import Page
from shiny.pytest import create_app_fixture

app = create_app_fixture("app.py")

def test_filter_updates_table(page: Page, app):
    page.goto(app.url)
    page.locator("#threshold").fill("4")
    page.locator("#apply").click()
    assert page.locator("#table tbody tr").count() == 2
```

For code examples, see `references/examples.md`.
