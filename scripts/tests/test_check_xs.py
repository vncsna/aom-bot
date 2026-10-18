#!/usr/bin/env python3
"""Regression tests for scripts/check_xs.py.

Each case is a snippet the engine rejects, paired with the message the checker must
produce, one per kind of error the checker guards against.
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CHECK = Path(__file__).resolve().parent.parent / "check_xs.py"

GAME_AI = Path(os.environ.get(
    "AOM_GAME_AI",
    Path.home() / ".local/share/Steam/steamapps/common/Age of Mythology Retold/game/ai",
))

CASES = {
    "switch without braces": (
        "void foo()\n{\n\tswitch (cMyCiv)\n\t{\n\t\tcase cCivZeus: bar(); break;\n\t}\n}\n",
        "braces",
        False,
    ),
    "call before definition": (
        "void caller()\n{\n\thelper();\n}\n\nvoid helper()\n{\n}\n",
        "used before it is defined",
        False,
    ),
    "array function called before definition": (
        "void caller()\n{\n\tint[] ids = helper();\n}\n\nint[] helper()\n{\n\treturn ids;\n}\n",
        "used before it is defined",
        False,
    ),
    "arithmetic left of a comparison": (
        "void foo(int a, int b)\n{\n\tif (a > 0 && a * 100 >= b * 5)\n\t{\n\t}\n}\n",
        "error 0308",
        False,
    ),
    "arithmetic left of a comparison across lines": (
        "void foo(int a, int b)\n{\n\tif (a > 0 &&\n\t\ta * 100 >= b)\n\t{\n\t}\n}\n",
        "error 0308",
        False,
    ),
    "default after a parameter without one": (
        "int near(vector location, float radius = 60.0)\n{\n\treturn 0;\n}\n",
        "error 0016",
        False,
    ),
    "parameter without a default": (
        "bool near(vector location)\n{\n\treturn true;\n}\n",
        "error 0016",
        False,
    ),
    "non-extern global": (
        "void foo()\n{\n\tgTitanGateCurrentState = 1;\n}\n",
        "not extern",
        True,
    ),
    "unknown constant": (
        "void foo()\n{\n\tint x = cNotARealConstant;\n}\n",
        "not a known constant",
        True,
    ),
    "unknown function": (
        "void foo()\n{\n\taiPlanGetIDsByTyp(cPlanAttack);\n}\n",
        "not a known function",
        True,
    ),
    "unknown rule": (
        'void foo()\n{\n\txsEnableRule("noSuchRule");\n}\n',
        "not defined anywhere",
        True,
    ),
}


class CheckXsTest(unittest.TestCase):
    def test_detects_known_failures(self):
        game_available = GAME_AI.is_dir()
        for name, (source, expected, needs_game) in CASES.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as tmp:
                if needs_game and not game_available:
                    self.skipTest("needs the game install")
                path = Path(tmp) / "case.xs"
                path.write_text(source)
                command = [sys.executable, str(CHECK), str(path)]
                if not game_available:
                    command.append("--no-game")
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn(expected, result.stdout, result.stdout)


if __name__ == "__main__":
    unittest.main()
