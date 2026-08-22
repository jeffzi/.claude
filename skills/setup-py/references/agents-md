# AGENTS.md

## Local overrides

If `AGENTS.local.md` exists at the repo root, read it and let its instructions take precedence over
this file. It is gitignored for personal, machine-specific preferences and never committed.

## Commands

`Taskfile.yml` wraps the common workflows — run `task --list` to see them. The recipes below are the
preferred entrypoints; each shells out to the underlying `uv` command shown after it.

- `task test` — `uv run pytest` (append args after `--`, e.g. `task test -- -k name`).
- `task test:matrix` — run the suite on every supported Python version.
- `task check` — `uv run prek run -a` (all hooks). Run before committing.
- `task check:fix` — auto-fix everything that supports it: `ruff check --fix`, `ruff format`,
  `dprint fmt`, markdownlint (via prek).
- `task clean` — remove build artifacts, caches, and virtualenvs.

Underlying commands, if you need them directly:

- `uv sync --all-groups` — install all dependencies (including the `dev` group) into `.venv`.
- `uv run pytest` — run the test suite with coverage; `fail_under` in `pyproject.toml` fails the
  run, and untested `src/` lines count against it.
- `uv run prek run -a` — all pre-commit hooks: Ruff lint + format, pyrefly, dprint, markdownlint,
  cspell, actionlint, zizmor. Run before committing.
- `uv run ruff check --fix` — lint and auto-fix Python.
- `uv run ruff format` — format Python.
- `uv run pyrefly check` — type-check.
- `uv run diff-cover coverage.xml --compare-branch=origin/main --fail-under=90` — enforce coverage
  on changed lines (run after `uv run coverage xml`).

## Git hygiene

- Never run `git commit --no-verify`, `git commit -n`, or anything else that skips the prek hooks —
  the hooks are the gate, not an obstacle.
- Fix a failing check at its source. Never edit a test to make it pass; never widen a lint ignore to
  silence a real finding.

## Anti-patterns

- No `pip install`, `python -m venv`, `requirements.txt`, or `setup.py` — this project is uv-managed.
  Add dependencies with `uv add` (`uv add --dev` for the dev group).
- Never call the tools bare (`pytest`, `ruff`, `pyrefly`, `python`). Always go through `uv run` so
  the command resolves the project's locked environment.
- Ruff is the only linter and formatter. Do not invoke Black, isort, flake8, or pylint.
