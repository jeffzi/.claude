---
name: code-py
description: >
  Use when writing any Python code, regardless of
  perceived simplicity or prototyping context.
---

# Pythonic Code - Python Best Practices

## Overview

Write production-quality Python code using type hints, modern features (3.10+), and Pythonic idioms.
**Core principle:** Every Python function gets type hints. Quick code becomes production code—write
it correctly the first time.

## Domain Skill Detection

When reviewing or writing Python code, check imports for domain-specific libraries. If detected,
load the corresponding skill for library-specific best practices:

| Import pattern                                    | Skill to load              |
| ------------------------------------------------- | -------------------------- |
| `import marimo` / `from marimo import`            | `code-marimo`              |
| `from shiny import` / `from shiny.express import` | `code-shiny`               |
| `import polars` / `from polars import`            | `scientific-skills:polars` |

Only load skills that are actually installed. If a skill fails to load, continue without it.

## Mandatory Rules

### No Obvious Comments

**Never explain what code does. Only explain WHY for non-obvious business logic.**

```python
# ✗ FORBIDDEN - Obvious comments
total = 0  # Initialize total to zero
for item in items:  # Loop through each item
    total += item  # Add item to total

# ✓ CORRECT - Self-documenting code
total = sum(items)
```

### Imports at Top of File

**ALWAYS place all imports at the top of the file.** No imports inside functions or conditional
blocks (except `if TYPE_CHECKING:`).

```python
# ✓ Correct
import os
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pandas import DataFrame

def my_function():
    pass

# ✗ Wrong - import inside function
def my_function():
    import os  # BAD
```

### Type Hints Are Not Optional

**ALWAYS add type hints to function signatures.** No exceptions for "simple" functions.

```python
# ✗ NEVER write this
def process(items):
    return [x ** 2 for x in items if x % 2 == 0]

# ✓ ALWAYS write this
def process(items: list[int]) -> list[int]:
    return [x ** 2 for x in items if x % 2 == 0]
```

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

```python
# ✗ Manual boilerplate
class Point:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

# ✓ Dataclass
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class Point:
    x: int
    y: int
```

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

## Quick Reference

### Common Patterns

| Task                | Pythonic Pattern                                         |
| ------------------- | -------------------------------------------------------- |
| Iterate over list   | `for item in items:` NOT `for i in range(len(items)):`   |
| List transformation | `[x**2 for x in nums if x % 2 == 0]`                     |
| Count occurrences   | `from collections import Counter; Counter(items)`        |
| Dict with defaults  | `from collections import defaultdict; defaultdict(int)`  |
| Safe dict access    | `my_dict.get(key, default)`                              |
| File operations     | `Path(filepath).read_text()` NOT `open(filepath).read()` |
| Check None          | `if value is None:` NOT `if value == None:`              |
| Check truthiness    | `if items:` NOT `if len(items) > 0:`                     |

### Type Hints Reference

```python
from typing import TYPE_CHECKING
from collections.abc import Callable, Iterable, Sequence

# Basic types
def func(x: int, y: str) -> bool: ...

# Collections (Python 3.10+)
def process(items: list[int]) -> dict[str, int]: ...

# Optional/Union
def find(key: str) -> str | None: ...
def parse(value: int | str) -> int: ...

# Callable
def apply(func: Callable[[int], str], x: int) -> str: ...

# Generic iterables
def count(items: Iterable[str]) -> int: ...

# Type-only imports (no runtime cost)
if TYPE_CHECKING:
    from expensive_module import ExpensiveClass

def process(data: ExpensiveClass) -> None: ...
```

### Pitfalls

| ✗ Never                           | ✓ Always                                            |
| --------------------------------- | --------------------------------------------------- |
| Obvious comments (`# add 1 to x`) | Self-documenting code, or explain WHY not WHAT      |
| Imports inside functions          | Imports at top of file (except `if TYPE_CHECKING:`) |
| `def func(items=[]):`             | `def func(items: list[int] \| None = None):`        |
| `for i in range(len(items)):`     | `for item in items:` or `enumerate(items)`          |
| `if value == None:`               | `if value is None:`                                 |
| `if len(items) > 0:`              | `if items:`                                         |
| `result += s` in loop             | `''.join(strings)`                                  |
| `open('file.txt')` without `with` | `with open('file.txt') as f:`                       |
| Bare `except:`                    | `except ValueError:` or `except Exception:`         |
| `os.path.*`                       | `pathlib.Path`                                      |
| Manual class for data             | `@dataclass`                                        |
| LBYL (check before act)           | EAFP (try/except)                                   |
| No type hints                     | Type hints on ALL function signatures               |
| Manual dict counting              | `Counter` or `defaultdict(int)`                     |

## Comprehensions and Generators

```python
# List comprehensions - simple transformations
squares = [x**2 for x in range(10)]
evens = [x for x in numbers if x % 2 == 0]

# Generator expressions - memory-efficient for large datasets
total = sum(x**2 for x in huge_list)
```

**When to use:**

- **List comprehension** `[x for x in items]`: Need multiple passes, small dataset
- **Generator** `(x for x in items)`: Single pass, large dataset

## Built-in Functions

Prefer built-in functions over manual loops—they're faster.

```python
# ✓ Use built-ins
total = sum(numbers)
maximum = max(values)
all_true = all(conditions)
any_true = any(conditions)
result = ', '.join(words)
```

## Error Handling

### Specific Exceptions

```python
# ✓ Catch specific exceptions
try:
    value = int(user_input)
except ValueError:
    print("Invalid number")

# ✗ Bare except catches KeyboardInterrupt, SystemExit
try:
    risky_operation()
except:  # BAD
    pass
```

### Exception Chaining

```python
# ✓ Preserve original traceback
try:
    process()
except ValueError as e:
    raise CustomError("Processing failed") from e
```

## Async Code Patterns

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

### TaskGroup for Structured Concurrency (Python 3.11+)

```python
async def main() -> None:
    """Run multiple services; cancel all if any fails."""
    async with asyncio.TaskGroup() as tg:
        task1 = tg.create_task(service1())
        task2 = tg.create_task(service2())
```

## Rationalizations That Mean You're About to Fail

| Excuse                                 | Reality                                                       |
| -------------------------------------- | ------------------------------------------------------------- |
| "No type hints - keeping it simple"    | Type hints ARE simple. They catch bugs at write-time.         |
| "Would add in production code, but..." | Quick code IS production code. Write it right the first time. |
| "This is the classic approach"         | Classic = outdated. Use modern Python features.               |
| "Felt more natural"                    | Natural ≠ Pythonic. Follow EAFP and idioms.                   |
| "Just prototyping"                     | Prototypes become production. No shortcuts.                   |

## Verification

**MANDATORY before completing any task:**

```bash
uv tool run prek run -a   # Linting and formatting (orchestrates ruff, basedpyright, dprint, etc.)
uv run pytest        # If tests/ exist — always run separately from linting
```

**Task is NOT complete until all pass.**
