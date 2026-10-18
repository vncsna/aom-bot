#!/usr/bin/env python3
"""Archive the bot's own output from a match, with a metadata header.

`custom_bot.xs` writes its diagnostics (`[CustomBot]`) and one telemetry line every
30 seconds (`[CBOT]`) to the local player's AI output log:

  …/Games/Age of Mythology Retold/temp/Logs/MythRetoldAIOutputPlayer1.txt

The engine truncates that file when the next session starts, so a match must be
archived before the next one begins:

  scripts/archive_run.py [notes about the match…]

Only the bot's own lines are kept, so an archive stays readable. It lands in
`runs/<stamp>-<map>.log` with a comment header naming the map and both players,
read from the sibling `MythLog.txt` and `MythAIConstantsPlayer<N>.txt`.
`scripts/parse_ai_log.py` reads the telemetry back out.
"""

import os
import re
import sys
from datetime import datetime
from pathlib import Path

LOGS = Path(os.environ.get(
    "AOM_LOGS",
    Path.home() / ".local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c"
    "/users/steamuser/Games/Age of Mythology Retold/temp/Logs",
))
RUNS = Path(os.environ.get("AOM_RUNS", Path(__file__).resolve().parent.parent / "runs"))

MARKERS = ("[CBOT]", "[CustomBot]")


def read_text(path):
    # The AI logs are UTF-16 (without a BOM); the constants files are ASCII.
    data = path.read_bytes()
    if b"\x00" in data[:64]:
        return data.decode("utf-16")
    return data.decode("utf-8", errors="replace")


def constant(lines, name):
    """Value of `const <type> c<name> = …;` in a MythAIConstants file."""
    pattern = re.compile(rf'^const (?:int|string) c{name} = "?([^";]+)"?;$')
    for line in lines:
        match = pattern.match(line.strip())
        if match:
            return match.group(1)
    return None


def constant_name(lines, prefix, value, skip=()):
    """Name of the `c<prefix><Name> = <value>` engine constant, if it has one."""
    pattern = re.compile(rf"^const int c{prefix}(\w+) = {value};$")
    for line in lines:
        match = pattern.match(line.strip())
        if match and match.group(1) not in skip:
            return match.group(1)
    return None


def describe_player(logs, player):
    path = logs / f"MythAIConstantsPlayer{player}.txt"
    if not path.is_file():
        return f"player {player}: unknown (no MythAIConstantsPlayer{player}.txt)"
    lines = read_text(path).splitlines()

    script = constant(lines, "Filename") or f"player {player}"
    # cPersonalityCurrent shares the cPersonality prefix but names no personality.
    personality = constant(lines, "PersonalityCurrent")
    label = (constant_name(lines, "Personality", personality, skip=("Current",))
             or f"personality {personality}")
    civ = constant(lines, "MyCiv")
    civname = constant_name(lines, "Civ", civ) or f"civ {civ}"
    culture = constant(lines, "MyCulture")
    culturename = constant_name(lines, "Culture", culture) or f"culture {culture}"

    return f"player {player}: {script}, {label}, {civname} ({culturename})"


def map_name(logs):
    path = logs / "MythLog.txt"
    if not path.is_file():
        return None
    for line in reversed(read_text(path).splitlines()):
        match = re.search(r"MAP CODE: '\d+/([^/]+)\.xs/", line)
        if match:
            return match.group(1)
    return None


def main():
    source = LOGS / "MythRetoldAIOutputPlayer1.txt"
    if not source.is_file():
        print(f"no such log: {source}", file=sys.stderr)
        return 2

    lines = [line for line in read_text(source).splitlines()
             if any(marker in line for marker in MARKERS)]
    if not lines:
        print(f"no bot output in {source.name} — archive it before starting the next match",
              file=sys.stderr)
        return 1

    now = datetime.now()
    mapname = map_name(LOGS) or "unknown"
    header = [
        f"# archived {now.strftime('%Y-%m-%d %H:%M:%S')}",
        f"# map: {mapname}",
        f"# {describe_player(LOGS, 1)}",
        f"# {describe_player(LOGS, 2)}",
    ]
    notes = " ".join(sys.argv[1:])
    if notes:
        header.append(f"# notes: {notes}")

    RUNS.mkdir(parents=True, exist_ok=True)
    dest = RUNS / f"{now.strftime('%Y%m%d-%H%M%S')}-{re.sub(r'[^\w.-]', '_', mapname)}.log"
    dest.write_text("\n".join(header + [""] + lines) + "\n")

    print(f"{dest} ({len(lines)} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
