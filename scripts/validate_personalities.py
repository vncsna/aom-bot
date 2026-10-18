#!/usr/bin/env python3
"""Validate the wiring around the mod's personalities.

XS itself cannot be linted here, but the files that point at it can: every
personality must be well-formed XML, reference a script that exists, and be
registered in personalities_mods.xml.
"""

import sys
from pathlib import Path
from xml.etree import ElementTree

AI_DIR = Path(__file__).resolve().parent.parent / "game" / "ai"
PERSONALITIES_DIR = AI_DIR / "personalities"

errors = []


def parse(path):
    try:
        return ElementTree.parse(path).getroot()
    except ElementTree.ParseError as exc:
        errors.append(f"{path.name}: not well-formed XML ({exc})")
        return None


for path in sorted(PERSONALITIES_DIR.glob("*.personality")):
    root = parse(path)
    if root is None:
        continue

    script = root.findtext("script")
    if not script:
        errors.append(f"{path.name}: missing <script>")
    elif not (AI_DIR / f"{script}.xs").is_file():
        errors.append(f"{path.name}: <script>{script}</script> has no game/ai/{script}.xs")

registry = PERSONALITIES_DIR / "personalities_mods.xml"
root = parse(registry)
if root is not None:
    for element in root.findall("Personality"):
        name = (element.text or "").strip()
        if not name:
            errors.append(f"{registry.name}: empty <Personality> entry")
        elif not (PERSONALITIES_DIR / f"{name}.personality").is_file():
            errors.append(f"{registry.name}: {name} has no {name}.personality")

if errors:
    print("\n".join(errors))
    sys.exit(1)

print("personality files OK")
