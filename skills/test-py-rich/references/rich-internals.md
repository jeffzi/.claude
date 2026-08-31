# Rich internals that shape tests

Facts from `rich/live.py`, `rich/live_render.py`, `rich/console.py`, `rich/progress.py` and rich's
own test suite (rich 15). Background for the rules in `SKILL.md`, not standing instructions.

## Contents

- [What `Live` emits](#what-live-emits)
- [Interactive vs terminal vs piped](#interactive-vs-terminal-vs-piped)
- [Height and vertical overflow](#height-and-vertical-overflow)
- [The three clock seams](#the-three-clock-seams)
- [Capture, record, export](#capture-record-export)
- [Console kwargs rich pins in its own tests](#console-kwargs-rich-pins-in-its-own-tests)
- [Nondeterministic tokens](#nondeterministic-tokens)
- [How rich and Textual test themselves](#how-rich-and-textual-test-themselves)

## What `Live` emits

Control codes (`rich/control.py`): `\r` carriage return, `\x1b[2K` erase line, `\x1b[{n}A` cursor
up, `\x1b[?25l` / `\x1b[?25h` hide/show cursor, `\x1b[?1049h/l` alt screen. Plus SGR for styles and
OSC 8 for hyperlinks. Nothing newer — no synchronized output, no Kitty protocol.

Per refresh on an interactive console (`Live.process_renderables`): `position_cursor()` — `\r`,
erase, then `\x1b[1A\x1b[2K` × (previous height − 1) — followed by anything printed this cycle and
the new block. The erase length is whatever the _previous_ frame measured (`LiveRender._shape`), so
one line added to a frame shifts every later escape in a raw capture. That is why goldens of the raw
stream are brittle and why the skill asserts frames, not streams.

On `stop()`, in order: `vertical_overflow = "visible"` (the last frame is always rendered in full),
final refresh, restore redirected stdio, trailing newline if anything was drawn, show cursor, then —
if `transient` — `restore_cursor()`: `\r` + `\x1b[1A\x1b[2K` × height. Show-cursor comes _before_
the erase.

"Print above the block": while `Live` runs with `redirect_stdout`/`redirect_stderr`, `sys.stdout`
and `sys.stderr` are swapped for a `FileProxy` that buffers until `\n`, decodes the line, and routes
it through `console.print`. The render hook sandwiches it: `position_cursor()`, the printed line,
the block redrawn below. `Progress` is a `Live` subclass and inherits all of this.

## Interactive vs terminal vs piped

`Live` refreshes only when `console.is_interactive` (`is_terminal and not is_dumb_terminal`, or
`force_interactive`). A `force_terminal=False` console emits **nothing during the run** and prints
the final frame once at `stop()` — zero escape codes. `console.control()` is also a no-op on dumb
terminals (`TERM=dumb`, which additionally hard-codes size to 80×25).

## Height and vertical overflow

`LiveRender.__rich_console__` compares the rendered height against `options.size.height`: `"crop"`
truncates, `"ellipsis"` truncates to height − 1 and appends `...`, `"visible"` lets it grow.
`_shape` is recomputed after truncation so the next erase matches what was drawn. A frame rendered
through a plain non-terminal console never sees this; rich needs `height=5` consoles and three
dedicated tests for it. Pin `height` whenever overflow is possible, and size a `pyte` screen
identically to the console.

## The three clock seams

Not interchangeable:

| Seam                     | Drives                                                                                                                            |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `Console(get_time=...)`  | `Spinner` / `Status` frame selection                                                                                              |
| `Progress(get_time=...)` | `TimeElapsedColumn`, `TimeRemainingColumn`, speed; `SpinnerColumn` _inside_ a Progress reads `task.get_time()`, which is this one |
| `Task(_get_time=...)`    | column-level unit tests without a console                                                                                         |

Rich's own `MockClock(auto=True)` advances on every _read_, so the number of clock reads becomes
part of the expected output. An explicit `tick()` between events is more robust downstream.

`SpinnerColumn` frames depend on the clock; with an injected clock they are stable in a golden.

## Capture, record, export

- `console.capture()` / `begin_capture()` returns the raw bytes-on-the-wire, escapes included.
- `Console(record=True)` + `export_text()` returns plain text with control segments dropped
  (`styles=True` keeps SGR but still drops cursor motion). `export_text(clear=True)` is the default
  and drains the buffer.
- While a capture is active nothing is recorded — the two are mutually exclusive by design
  (regression test for issue #2563; broke in 12.0.1 and again in 13.8.0).
- `export_text()` on a `Live` yields every frame concatenated, each newline-terminated, with no
  frame marker.
- `AnsiDecoder` round-trips styles but has no cursor model; it cannot tell "erased and redrawn" from
  "appended". Not a substitute for an emulator.

## Console kwargs rich pins in its own tests

```python
Console(
    file=StringIO(), width=..., height=...,    # size
    force_terminal=True | False,               # which branch
    color_system=None | "truecolor",           # None "to reduce complexity of output"
    legacy_windows=False,                      # skip the win32 renderer branch
    _environ={},                               # seals COLUMNS, LINES, TERM, COLORTERM, NO_COLOR,
                                               # FORCE_COLOR, TTY_COMPATIBLE, TTY_INTERACTIVE, JUPYTER_*
    get_time=lambda: 0.0,                      # spinner/status only
)
```

`_environ={}` removes the inputs to color detection, so pair it with an explicit `color_system` (or
`no_color=True`) and `force_terminal`; otherwise the sealing itself becomes the variable. Textual
does the same in production (`App.__init__` passes `_environ=` and eight pinned kwargs).

## Nondeterministic tokens

- OSC 8 hyperlink ids embed a random id and an absolute path: `\x1b]8;id=7538922;https://…`. A
  non-terminal console never emits OSC 8, and `pyte` consumes it during replay, so this only matters
  for exact raw-escape assertions. Rich and Textual both normalize with
  `re.sub(r"id=[\d.\-]*?;.*?\x1b", "id=0;foo\x1b", out)` inside a shared `render()` helper.
- Timestamps: `Console(log_time_format="[TIME]", log_path=False)`.
- `export_svg` class ids: `terminal-<digits>-`, normalized by `pytest-textual-snapshot`.

## How rich and Textual test themselves

- **Rich** asserts the raw escape stream verbatim (`begin_capture()` → one large `==`), because the
  stream _is_ its contract. No snapshot plugin, no emulator, no pty. `test_live.py` pins transient
  erase as the tail of an exact string; `test_status.py` skips live output entirely
  (`# TODO: Testing output is tricky with threads`); `test_live.py` leaves the auto-refresh thread
  untested (`# no way to truly test w/ multithreading`).
- **Textual** never emits cursor codes in tests: `HeadlessDriver.write()` is a no-op and the screen
  is reconstructed from the compositor into an SVG (`Console(record=True).export_svg`) snapshotted
  with syrupy — 345 snapshot tests of ~2,000, reserved for "visual elements". Below the app it uses
  the same `render()` helper as rich and asserts exact styled strings with named constants
  (`MAGENTA = "\x1b[35m"`), or structured data: `Segment` lists, `Strip` rows flattened to text,
  `Bar.render().highlight_range`.
- Neither uses `pyte`. For plain rich `Live`, an emulator is the substitute for the compositor
  Textual has and rich doesn't need.
