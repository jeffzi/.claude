"""Tests for the setup-py `check_max_lines.py` reference script.

The script is a template (no package), so it is loaded from its path in
`skills/setup-py/references/scripts/`.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import pytest

_SCRIPT_PATH = (
    Path(__file__).resolve().parents[1]
    / "skills"
    / "setup-py"
    / "references"
    / "scripts"
    / "check_max_lines.py"
)


def _load_script() -> ModuleType:
    spec = importlib.util.spec_from_file_location("check_max_lines", _SCRIPT_PATH)
    if spec is None or spec.loader is None:
        msg = f"cannot load {_SCRIPT_PATH}"
        raise ImportError(msg)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check_max_lines = _load_script()
_SRC_LIMIT = check_max_lines.MAX_LINES_SRC
_TEST_LIMIT = check_max_lines.MAX_LINES_TEST
_FN_LIMIT = check_max_lines.MAX_LINES_PER_FUNCTION


def _write_code_lines(path: Path, count: int) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("x = 1\n" * count)
    return path


def _write_function(path: Path, code_lines: int) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("def big():\n" + "    x = 1\n" * (code_lines - 1))
    return path


@pytest.mark.parametrize(
    ("relative_path", "code_lines", "expected_exit"),
    [
        pytest.param("module.py", _SRC_LIMIT, 0, id="src-at-limit"),
        pytest.param("module.py", _SRC_LIMIT + 1, 1, id="src-over-limit"),
        pytest.param("test_module.py", _SRC_LIMIT + 1, 0, id="test-prefix-gets-800"),
        pytest.param("module_test.py", _SRC_LIMIT + 1, 0, id="test-suffix-gets-800"),
        pytest.param("tests/module.py", _SRC_LIMIT + 1, 0, id="tests-dir-gets-800"),
        pytest.param("tests/test_module.py", _TEST_LIMIT + 1, 1, id="test-over-limit"),
    ],
)
def test_main_when_file_at_or_over_limit_does_return_matching_exit(
    tmp_path, relative_path, code_lines, expected_exit
):
    file = _write_code_lines(tmp_path / relative_path, code_lines)

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == expected_exit


def test_main_when_over_limit_does_report_path_count_and_limit(tmp_path, capsys):
    file = _write_code_lines(tmp_path / "module.py", _SRC_LIMIT + 1)

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 1
    assert capsys.readouterr().out == f"{file}: {_SRC_LIMIT + 1} code lines (max {_SRC_LIMIT})\n"


def test_main_when_comments_and_blanks_present_does_not_count_them(tmp_path):
    file = tmp_path / "module.py"
    file.write_text("# comment\n\nx = 1\n" * _SRC_LIMIT)

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 0


def test_main_when_multiline_string_present_does_count_every_line(tmp_path, capsys):
    file = tmp_path / "module.py"
    file.write_text("x = 1\n" * (_SRC_LIMIT - 2) + 's = """\na\nb\n"""\n')

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 1
    assert f"{_SRC_LIMIT + 2} code lines (max {_SRC_LIMIT})" in capsys.readouterr().out


def test_main_when_multiline_string_has_blank_lines_does_not_count_them(tmp_path):
    file = tmp_path / "module.py"
    file.write_text("x = 1\n" * (_SRC_LIMIT - 4) + 's = """\na\n\nb\n"""\n')

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 0


def _missing_file(tmp_path: Path) -> Path:
    return tmp_path / "absent.py"


def _untokenizable_file(tmp_path: Path) -> Path:
    file = tmp_path / "broken.py"
    file.write_text('x = "unterminated\n')
    return file


@pytest.mark.parametrize(
    "make_file",
    [
        pytest.param(_missing_file, id="missing-file"),
        pytest.param(_untokenizable_file, id="tokenize-error"),
    ],
)
def test_main_when_file_cannot_be_read_does_report_error_and_return_one(
    tmp_path, capsys, make_file
):
    file = make_file(tmp_path)

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 1
    out = capsys.readouterr().out
    assert out.startswith(f"{file}: could not read (")
    assert out.endswith(")\n")


def test_main_when_a_file_cannot_be_read_does_still_check_later_files(tmp_path, capsys):
    missing = _missing_file(tmp_path)
    big = _write_code_lines(tmp_path / "big.py", _SRC_LIMIT + 1)

    exit_code = check_max_lines.main([str(missing), str(big)])

    assert exit_code == 1
    out = capsys.readouterr().out
    assert f"{missing}: could not read (" in out
    assert f"{big}: {_SRC_LIMIT + 1} code lines (max {_SRC_LIMIT})\n" in out


def test_main_when_multiple_files_does_report_only_offenders(tmp_path, capsys):
    good = _write_code_lines(tmp_path / "small.py", 10)
    bad = _write_code_lines(tmp_path / "big.py", _SRC_LIMIT + 1)

    exit_code = check_max_lines.main([str(good), str(bad)])

    assert exit_code == 1
    out = capsys.readouterr().out
    assert str(bad) in out
    assert str(good) not in out


@pytest.mark.parametrize(
    ("relative_path", "code_lines", "argv_prefix", "expected_exit"),
    [
        pytest.param(
            "module.py", _SRC_LIMIT + 1, ["--max-lines", str(_SRC_LIMIT + 1)], 0, id="raised-src"
        ),
        pytest.param("test_module.py", 11, ["--max-lines-test", "10"], 1, id="lowered-test"),
    ],
)
def test_main_when_max_lines_flags_given_does_override_defaults(
    tmp_path, relative_path, code_lines, argv_prefix, expected_exit
):
    file = _write_code_lines(tmp_path / relative_path, code_lines)

    exit_code = check_max_lines.main([*argv_prefix, str(file)])

    assert exit_code == expected_exit


def test_main_when_function_exceeds_limit_does_report_name_line_and_count(tmp_path, capsys):
    file = _write_function(tmp_path / "module.py", _FN_LIMIT + 1)

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 1
    out = capsys.readouterr().out
    assert out == f"{file}:1: function 'big' has {_FN_LIMIT + 1} code lines (max {_FN_LIMIT})\n"


def test_main_when_function_at_limit_with_blanks_and_comments_does_pass(tmp_path):
    file = tmp_path / "module.py"
    file.write_text("def big():\n    # comment\n\n" + "    x = 1\n" * (_FN_LIMIT - 1))

    exit_code = check_max_lines.main([str(file)])

    assert exit_code == 0


@pytest.mark.parametrize(
    ("relative_path", "argv_prefix", "expected_exit"),
    [
        pytest.param("test_module.py", [], 0, id="test-file-skipped-by-default"),
        pytest.param(
            "test_module.py",
            ["--max-lines-per-function-test", str(_FN_LIMIT)],
            1,
            id="test-flag-enables",
        ),
        pytest.param("module.py", ["--max-lines-per-function", "0"], 0, id="zero-disables"),
    ],
)
def test_main_when_function_limit_flags_vary_does_gate_the_check(
    tmp_path, relative_path, argv_prefix, expected_exit
):
    file = _write_function(tmp_path / relative_path, _FN_LIMIT + 1)

    exit_code = check_max_lines.main([*argv_prefix, str(file)])

    assert exit_code == expected_exit
