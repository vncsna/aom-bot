#!/usr/bin/env python3
"""Enforce the complexity budget for god_bot.xs.

The bot grows by accretion unless it is capped, so the countable metrics are limited
and checked in CI. See the "Complexity Budget" section of AGENTS.md for why each limit
exists and the rule for changing one.

Counts are structural, not semantic: they cannot see a plan stealing another plan's
units, only that the file is not getting bigger. The invariants that need judgement
stay in AGENTS.md.

Usage:
    scripts/check_budget.py [file]
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TARGET = REPO / "game/ai/god_bot.xs"

# Keep in sync with the table in AGENTS.md.
LIMITS = {
    "lines": 1500,
    "rules": 10,
    "consts": 30,
    "globals": 20,
}

RULE = re.compile(r"^rule\s+\w+")
CONST = re.compile(r"^const\s+\w+\s+(c\w+)\s*=")
GLOBAL = re.compile(r"^(?:bool|int|float|string|vector)(?:\[\])?\s+(g\w+)\s*=")


def count(lines):
    return {
        "lines": len(lines),
        "rules": sum(1 for line in lines if RULE.match(line)),
        "consts": sum(1 for line in lines if CONST.match(line)),
        "globals": sum(1 for line in lines if GLOBAL.match(line)),
    }


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    target = Path(args[0]) if args else TARGET
    counts = count(target.read_text().splitlines())
    rel = target.relative_to(REPO) if REPO in target.parents else target

    failed = False
    for name, limit in LIMITS.items():
        value = counts[name]
        state = "OK" if value <= limit else "OVER"
        print(f"{rel}: {name} {value}/{limit} {state}")
        if value > limit:
            failed = True
    if failed:
        print(f"{rel}: over the complexity budget; see AGENTS.md", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
