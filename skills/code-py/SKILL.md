---
name: code-py
description: >
  Use when writing any Python code, regardless of perceived simplicity or prototyping context.
  Use when you think code is "just a quick script" or "types slow me down" — these are symptoms
  this skill applies. Not for marimo notebook patterns — use code-marimo. Not for Shiny UI
  patterns — use code-shiny. For tests, also load test-py. Applies to *.py files.
user-invocable: false
---

# Pythonic Code - Python Best Practices

**This skill extends `Skill(code-core)`.** `code-core` is the primary entry point; this skill is
loaded by `code-core` based on the rules-file dispatch table.

Check `pyproject.toml` `requires-python` for version-specific syntax (e.g., PEP 758 in 3.14+).

## Domain Skill Detection

When reviewing or writing Python code, check imports for domain-specific libraries. If detected,
load the corresponding skill for library-specific best practices:

| Import pattern                                    | Skill to load |
| ------------------------------------------------- | ------------- |
| `import marimo` / `from marimo import`            | `code-marimo` |
| `from shiny import` / `from shiny.express import` | `code-shiny`  |
| `import polars` / `from polars import`            | `polars`      |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Mandatory Rules

### Imports at Top of File

**ALWAYS place all imports at the top of the file.** No imports inside functions or conditional
blocks (except `if TYPE_CHECKING:`).

### Docstrings

**Internal functions:** Types + clear names suffice. Add docstrings only for non-obvious logic, side
effects, or public API.

### Use Modern Python Features

**Python 3.10+ syntax:**

| Instead of                    | Use                           |
| ----------------------------- | ----------------------------- |
| `List[int]`, `Dict[str, int]` | `list[int]`, `dict[str, int]` |
| `Optional[str]`               | `str \| None`                 |
| `Union[int, str]`             | `int \| str`                  |
| `os.path.*`                   | `pathlib.Path`                |
| Manual class                  | `@dataclass`                  |

### Dataclasses Over Manual Classes

Default to `@dataclass(frozen=True, slots=True)` for data containers.

**When to use alternatives:**

Check `pyproject.toml` for specialized libraries:

- **Pydantic** (if in dependencies): Use for data validation
- **msgspec** (if in dependencies): Use for fast JSON/MessagePack parsing
- **dataclasses**: Use for simple data containers

### EAFP Over LBYL

**Prefer "Easier to Ask Forgiveness than Permission"** over "Look Before You Leap".

```python
# ✗ LBYL
from pathlib import Path

def read_file(filepath: str) -> str | None:
    path = Path(filepath)
    if path.exists():
        return path.read_text()
    return None

# ✓ EAFP
def read_file(filepath: str) -> str | None:
    try:
        return Path(filepath).read_text()
    except FileNotFoundError:
        return None
```

## Unparenthesized Except (Python 3.14+, PEP 758)

Python 3.14+ allows omitting parentheses around multiple exception types in `except` and `except*`
clauses **when `as` is not used**. This is NOT the old Python 2 syntax — it is valid modern Python.
Check `pyproject.toml` `requires-python` before flagging this as an issue.

```python
# ✓ Valid Python 3.14+ — catches both exceptions (PEP 758)
except ValueError, TypeError:
    ...

# ✓ Valid Python 3.14+ — except* variant
except* OSError, RuntimeError:
    ...

# ✓ Parentheses REQUIRED when using `as`
except (ValueError, TypeError) as e:
    ...

# ✗ INVALID — cannot omit parentheses with `as`
except ValueError, TypeError as e:  # SyntaxError in 3.14+, ambiguous in <3.14
    ...
```

## Async Code Patterns

Use `asyncio.TaskGroup` (3.11+) for structured concurrency; sibling failure cancels the group.

### Bounded Concurrency

Always limit concurrent tasks to prevent memory exhaustion:

```python
from asyncio import Semaphore
import asyncio

async def fetch_all(urls: list[str], max_concurrent: int = 100) -> list[str]:
    """Fetch URLs with bounded concurrency."""
    sem = Semaphore(max_concurrent)

    async def fetch_one(url: str) -> str:
        async with sem:
            return await fetch(url)

    tasks = [asyncio.create_task(fetch_one(url)) for url in urls]
    return await asyncio.gather(*tasks)
```

## Rationalizations That Mean You're About to Fail

| Excuse                         | Reality                                         |
| ------------------------------ | ----------------------------------------------- |
| "This is the classic approach" | Classic = outdated. Use modern Python features. |
| "Felt more natural"            | Natural ≠ Pythonic. Follow EAFP and idioms.     |

## Verification

Run the gates the project exposes — check `pyproject.toml`, a pre-commit config, a
Makefile/justfile, or CI config to find them — using the project's own environment manager (`uv`,
`poetry`, `hatch`, plain venv) for every command. Run the test suite separately from linting. If the
project exposes no lint gate, fall back to `uv tool run prek run -a`.
