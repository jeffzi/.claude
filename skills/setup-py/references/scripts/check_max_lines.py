"""Fail when a Python file exceeds the max code-line counts.

Counts lines the way oxlint's ``max-lines`` does with ``skipBlankLines`` and
``skipComments``: blank lines and comment-only lines are free — including
whitespace-only lines inside multi-line strings and docstrings; every other
line touched by a token (code, strings, docstrings) counts once.

Two checks per file, mirroring oxlint's size rules:

- ``max-lines`` — whole-file code-line count. Default 400 for source files,
  800 for test files.
- ``max-lines-per-function`` — per-function code-line count. Default 60 for
  source files, disabled for test files. A limit of 0 disables the check.

Test files are those under a ``tests/`` directory or named ``test_*.py`` /
``*_test.py``. All limits are configurable via CLI flags — see ``--help``.
"""

# scripts/ holds standalone entry points, not an importable package — INP001 does not apply.
# ruff: noqa: INP001

from __future__ import annotations

import argparse
import ast
import io
import sys
import tokenize
from pathlib import Path

MAX_LINES_SRC = 400
MAX_LINES_TEST = 800
MAX_LINES_PER_FUNCTION = 60
MAX_LINES_PER_FUNCTION_TEST = 0

_NON_CODE_TOKENS = frozenset(
    {
        tokenize.COMMENT,
        tokenize.NL,
        tokenize.NEWLINE,
        tokenize.INDENT,
        tokenize.DEDENT,
        tokenize.ENDMARKER,
    }
)


def _code_line_numbers(source: str) -> set[int]:
    lines = source.splitlines()
    touched: set[int] = set()
    for token in tokenize.generate_tokens(io.StringIO(source).readline):
        if token.type == tokenize.ERRORTOKEN:
            # Pre-3.12 tokenizers emit ERRORTOKEN and keep going where the C
            # tokenizer raises TokenError; normalize to the raising behavior.
            msg = "invalid token"
            raise tokenize.TokenError(msg, token.start)
        if token.type in _NON_CODE_TOKENS:
            continue
        touched.update(range(token.start[0], token.end[0] + 1))
    return {number for number in touched if lines[number - 1].strip()}


def _oversized_functions(
    source: str, code_lines: set[int], limit: int
) -> list[tuple[str, int, int]]:
    """Return ``(name, lineno, count)`` for each function over ``limit`` code lines."""
    oversized: list[tuple[str, int, int]] = []
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        end = node.end_lineno or node.lineno
        count = sum(1 for number in code_lines if node.lineno <= number <= end)
        if count > limit:
            oversized.append((node.name, node.lineno, count))
    return oversized


def _is_test_file(path: Path) -> bool:
    return "tests" in path.parts or path.name.startswith("test_") or path.name.endswith("_test.py")


def _report(message: str) -> int:
    sys.stdout.write(f"{message}\n")
    return 1


def _check_file(path: Path, args: argparse.Namespace) -> int:
    is_test = _is_test_file(path)
    file_limit = args.max_lines_test if is_test else args.max_lines
    function_limit = args.max_lines_per_function_test if is_test else args.max_lines_per_function
    try:
        with tokenize.open(path) as handle:
            source = handle.read()
        code_lines = _code_line_numbers(source)
        oversized = (
            _oversized_functions(source, code_lines, function_limit) if function_limit else []
        )
    except (OSError, UnicodeDecodeError, SyntaxError, tokenize.TokenError) as exc:
        return _report(f"{path}: could not read ({exc})")
    exit_code = 0
    if len(code_lines) > file_limit:
        exit_code = _report(f"{path}: {len(code_lines)} code lines (max {file_limit})")
    for name, line, count in oversized:
        exit_code = _report(
            f"{path}:{line}: function '{name}' has {count} code lines (max {function_limit})"
        )
    return exit_code


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("files", nargs="*", type=Path, help="files to check")
    parser.add_argument(
        "--max-lines",
        type=int,
        default=MAX_LINES_SRC,
        help="code-line limit for source files (default: %(default)s)",
    )
    parser.add_argument(
        "--max-lines-test",
        type=int,
        default=MAX_LINES_TEST,
        help="code-line limit for test files (default: %(default)s)",
    )
    parser.add_argument(
        "--max-lines-per-function",
        type=int,
        default=MAX_LINES_PER_FUNCTION,
        help="per-function code-line limit for source files; 0 disables (default: %(default)s)",
    )
    parser.add_argument(
        "--max-lines-per-function-test",
        type=int,
        default=MAX_LINES_PER_FUNCTION_TEST,
        help="per-function code-line limit for test files; 0 disables (default: %(default)s)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Check each file; return 1 if any is unreadable or exceeds a limit."""
    args = _parse_args(argv)
    exit_code = 0
    for path in args.files:
        exit_code |= _check_file(path, args)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
