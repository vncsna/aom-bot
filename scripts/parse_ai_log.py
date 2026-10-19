#!/usr/bin/env python3
"""Summarise the bot's `[GBOT]` telemetry from an AI output log.

The bot writes one `[GBOT] ...` line every 30 seconds (see
`godTelemetryMonitor` in `game/ai/god_bot.xs`). The game puts those in a
per-player log:

  …/Games/Age of Mythology Retold/temp/Logs/MythRetoldAIOutputPlayer<N>.txt

That file is UTF-16. This reads it, pulls out the telemetry lines and prints a
table so a match can be reasoned about after the fact.

Usage:
  scripts/parse_ai_log.py <path-to-log>
"""

import sys
from pathlib import Path

MARKER = "[GBOT]"
COLUMNS = ["t", "age", "vills", "pop", "army", "food", "wood", "gold", "enemyAge", "enemyTitan", "titans", "wonder", "state", "underAttack", "enemies", "allies", "stance"]


def read_lines(path):
    # The game writes these logs as UTF-16; fall back to UTF-8 if that fails.
    try:
        text = path.read_text(encoding="utf-16")
    except (UnicodeError, UnicodeDecodeError):
        text = path.read_text(encoding="utf-8", errors="replace")
    return text.splitlines()


def parse_fields(line):
    fields = {}
    for token in line.split(MARKER, 1)[1].split():
        key, sep, value = token.partition("=")
        if sep:
            fields[key] = value
    return fields


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"no such file: {path}", file=sys.stderr)
        return 2

    rows = [parse_fields(line) for line in read_lines(path) if MARKER in line]
    if not rows:
        print("no [GBOT] telemetry found in this log")
        return 1

    print(" ".join(f"{c:>8}" for c in COLUMNS))
    for row in rows:
        print(" ".join(f"{row.get(c, '?'):>8}" for c in COLUMNS))
    print(f"\n{len(rows)} samples from {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
