#!/usr/bin/env python3
"""Tests for scripts/check_budget.py.

The budget is only a limit if exceeding it fails, so the cases are a file at the
ceiling and one past it.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECK = Path(__file__).resolve().parent.parent / "check_budget.py"
TARGET = Path(__file__).resolve().parent.parent.parent / "game/ai/god_bot.xs"


def run(text):
    with tempfile.NamedTemporaryFile("w", suffix=".xs", delete=False) as handle:
        handle.write(text)
        path = handle.name
    return subprocess.run(
        [sys.executable, str(CHECK), path], capture_output=True, text=True,
    )


class BudgetTest(unittest.TestCase):
    def test_current_file_passes(self):
        result = subprocess.run(
            [sys.executable, str(CHECK), str(TARGET)], capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_over_budget_fails(self):
        rules = "\n".join(f"rule r{i}\n{{\n}}" for i in range(11))
        result = run(rules + "\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("rules 11/10 OVER", result.stdout)

    def test_under_budget_passes(self):
        result = run("rule one\n{\n}\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
