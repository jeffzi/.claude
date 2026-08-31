---
name: test-py-rich
description: >
  Use when writing or reviewing pytest tests for terminal output built with rich — Live, Progress,
  Tree, Table, Panel, Console — including rich-based stderr progress/status renderers. Apply when
  a test captures Console(file=StringIO()) output, asserts on ANSI escape codes ("\x1b[" in
  output), checks a bare substring or digit in rendered text, needs golden snapshots of a frame,
  or replays output through a pyte terminal emulator. Not for non-rich CLI output — use test-py.
  Not for Textual apps.
user-invocable: false
---

# Testing rich Terminal Output

**This skill extends `Skill(test-core)` via `Skill(test-py)`.** It decides _what surface_ a rich
test asserts on — frame text, golden files, or an emulated screen — so tests pin layout and content
without coupling to rich's escape stream.

## Choosing the assertion surface

| Behavior under test                                | Surface                    | Assert with                            |
| -------------------------------------------------- | -------------------------- | -------------------------------------- |
| What a frame shows (layout, glyphs, counts, ETA)   | plain-text frame           | syrupy golden (multi-line) / `==` line |
| Single milestone line (plain mode, summary)        | captured console text      | exact `==` on the line                 |
| Rich-owned live effects (transient, redirect)      | how `Live` was constructed | `transient=`, `console.print` during   |
| Screen after code that bypasses rich / pty run     | `pyte` screen              | whole `screen.display` row list        |
| Color/TTY precedence, width resolution             | `Console` attributes       | `console.no_color`, `console.width`    |
| That styling is actually emitted                   | raw output of a tiny print | `"\x1b[" in out` / `not in out`        |
| State a seam already exposes (task counts, ETA ms) | the object, not its render | `progress.tasks[0].completed == 3`     |
| Wiring (signal cleanup registered, fan-out)        | fakes / monkeypatch        | recorded calls                         |
| The real TTY path end to end                       | one `pty` smoke test       | exit code + stripped text              |

Never assert on the raw buffer a `Live` wrote to: it is paint history, not what the user sees. Raw
escape codes are asserted only in the "styling is emitted" row, where the color is the behavior.

## Mandatory Rules

### 1. Renderers expose a frame; tests render it without a terminal

A renderer that drives `Live` must expose its current renderable through a public method (`frame()`)
— the same method its own `Live` renders from, not an accessor added for tests. Tests render that
frame through a throwaway non-terminal console at a fixed width:

```python
def frame_text(renderable: RenderableType, *, width: int = 100) -> str:
    buffer = StringIO()
    console = Console(file=buffer, width=width, force_terminal=False, no_color=True, _environ={})
    console.print(renderable)
    return buffer.getvalue()
```

Never build a live-mode renderer on a `force_terminal=False` console to "see the frames" — a
non-terminal `Live` emits nothing during the run and prints only the final frame at `stop()`
(`references/rich-internals.md`). Render `frame()` directly instead.

### 2. Multi-line frames are syrupy goldens; single lines are exact equality

```python
def test_frame_when_one_task_failed_and_one_running_does_match(snapshot):
    renderer = ...  # feed events to the state you want
    assert frame_text(renderer.frame()) == snapshot
```

- One golden per _named scenario_ (all pending, mid-run progress, completed with failures, final
  summary, narrow-width layout). A handful per renderer.
- Pin `width` (and `height` if it selects a layout) — a golden is stable only at one width.
- Update with `pytest --snapshot-update` only after reading the diff; a golden that accepts a
  regression is worse than no golden.
- Plain-mode milestone lines: `assert output == "[00:00:05] step one done (5s)\n"` — not
  `"[" in output`.
- Goldens need the `syrupy` dev dependency, added through the project's dependency manager.

### 3. Rich-owned live effects are wiring; screen state is for code that bypasses rich

Transient erase, a verbosity flag that keeps the block, and "warn prints above the block" are
`Live`'s contract (`references/rich-internals.md` § How rich and Textual test themselves). Assert
_your_ side: the `Live` was built with `transient=not verbose`, the warning went through
`console.print` while the block was up. Do not re-prove the erase.

What remains on the terminal is yours to test only where your code writes past rich — a signal
handler clearing the line with a raw `\r\x1b[K`, or a pty end-to-end run. There, replay the captured
stream through the `pyte` terminal emulator (a dev dependency) sized like the console:

```python
def screen_lines(raw: str, *, width: int = 100, height: int = 24) -> list[str]:
    screen = pyte.Screen(width, height)
    # a tty translates LF to CR+LF; pyte does not — without LNM the screen garbles
    screen.set_mode(pyte.modes.LNM)
    pyte.Stream(screen).feed(raw)
    return [line.rstrip() for line in screen.display if line.strip()]

def test_clear_on_signal_when_live_up_does_leave_screen_clean(monkeypatch):
    buffer = StringIO()
    console = Console(
        file=buffer, width=100, height=24,
        force_terminal=True, color_system="truecolor", _environ={},
    )
    renderer = build_renderer(console)          # Live is up, frame painted
    monkeypatch.setattr(sys, "stderr", buffer)  # the handler writes raw to stderr
    renderer.clear_on_signal()
    assert screen_lines(buffer.getvalue()) == []  # our raw write left the screen clean
```

Two or three such tests per project is the ceiling; content belongs in Rule 2.
`Console(record=True).export_text()` is no substitute (`references/rich-internals.md`).

### 4. No assertion that an escape sequence could satisfy

`"5" in output` and `"[" in output` both match inside `\x1b[35m`. A digit-or-bracket substring is
not an assertion; neither is `a in out or b in out`, a conditional `if output.count(...)`, or a scan
like `any(x in line for line in lines)` or `sum(1 for n in names if n in text)`. A frame or screen
is asserted as a whole — a golden, or
`screen_lines(raw) == ["run https://x.y", "├── ✔ build", "└── ○ test"]` — never by probing rows for
a word. When the renderer exposes the state (`Progress.tasks[n].completed`, a node's status, the ETA
value) assert on the object instead. The one legitimate escape-code assertion is the styling row
above: `"\x1b["` present or absent in a one-line print.

### 5. Deterministic frames

- Inject the clock at the seam that reads it and pass the same clock into your own ETA math; advance
  it explicitly between events. The seams are not interchangeable — `references/rich-internals.md` §
  The three clock seams.
- `Progress(auto_refresh=False)` and `Live(auto_refresh=False)`; call `refresh()` yourself. No
  refresh threads, no `time.sleep`.
- Fix `width`/`height` on every console; never read the real terminal size. Test compact or narrow
  layouts by constructing the console at that size.
- Seal the console from the developer's environment: `_environ={}` (or `monkeypatch.delenv` for
  `COLUMNS`, `LINES`, `TERM`, `COLORTERM`, `NO_COLOR`, `FORCE_COLOR`), explicit `force_terminal`,
  and an explicit color pin — `no_color=True`, `color_system=None`, or `color_system="truecolor"`
  for a `pyte` replay (why: `references/rich-internals.md` § Console kwargs). Pin
  `legacy_windows=False` when a golden must match across platforms.

### 6. Test your content, not rich

Bar glyphs, column spacing, and tree guides are rich's contract; a golden or a whole-screen `pyte`
row list pins them incidentally. A standalone assertion whose subject _is_ the glyph —
`"━━━╺" in
out`, `"├──" in line` — tests the library; delete it. Test _your_ label, count, glyph,
ETA text, and ordering.

## Verification

```bash
pytest                    # goldens under tests/__snapshots__/ are committed
pytest --snapshot-update  # only after reviewing the failing diff
```

## Rationalizations

| Excuse                                              | Reality                                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------------------ |
| "The StringIO has the text, substring is enough"    | It has paint history. `"5" in output` matches `\x1b[35m`.                            |
| "Goldens are brittle"                               | Goldens at fixed width fail only when the frame changes — the point.                 |
| "`\x1b[2K` in output proves the erase"              | Erasing is rich's job. Assert `transient=True` was passed, or replay through `pyte`. |
| "I'll call `_build_renderable()`, it's right there" | Private access couples the test to internals. Expose `frame()`.                      |
| "One assertion with `or` covers both layouts"       | Then it verifies neither. Build the console at each size; assert each.               |
| "A golden per event keeps coverage high"            | Thirty near-identical goldens get rubber-stamped on the first update.                |
