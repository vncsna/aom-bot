#!/usr/bin/env python3
"""Static checks for god_bot.xs.

The engine compiles XS only at match start and reports one error at a time, so every
mistake costs a full game load to find. These checks encode the rules we have verified
against the shipped base-game scripts; see docs/xs-syntax.md for the reasoning behind
each one.

Some checks need the game installed to know which symbols exist. Pass --no-game to run
only the checks that work from this repository alone (used by CI).

Usage:
    scripts/check_xs.py [file ...] [--no-game]
"""
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_TARGETS = [REPO / "game/ai/god_bot.xs"]

GAME_AI = Path(os.environ.get(
    "AOM_GAME_AI",
    Path.home() / ".local/share/Steam/steamapps/common/Age of Mythology Retold/game/ai",
))
CONSTANTS = Path(os.environ.get(
    "AOM_CONSTANTS",
    Path.home() / ".local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c/users"
    / "steamuser/Games/Age of Mythology Retold/temp/Logs/MythAIConstantsPlayer1.txt",
))

KEYWORDS = {
    "if", "else", "for", "while", "switch", "case", "default", "break", "continue",
    "return", "new", "ref", "void", "bool", "int", "float", "string", "vector",
    "rule", "inactive", "active", "minInterval", "maxInterval", "runImmediately",
    "highFrequency", "group", "include", "const", "static", "extern", "mutable",
    "true", "false", "size", "add",
}

FUNC_DEF = re.compile(r"^\s*(mutable\s+)?(?:void|bool|int|float|string|vector|Strategy)(?:\[\])?\s+(\w+)\s*\(")
CALL = re.compile(r"\b([a-z]\w*)\s*\(")
CASE = re.compile(r"^\s*case\b.*:\s*$")
CASE_INLINE = re.compile(r"^\s*case\b.*:\s*\S")
RULE_DEF = re.compile(r"^\s*rule\s+(\w+)")
RULE_USE = re.compile(r'xs(?:EnableRule|DisableRule|IsRuleEnabled|RuleIgnoreIntervalOnce)\(\s*"(\w+)"')
GLOBAL_DEF = re.compile(r"^\s*(?:bool|int|float|string|vector)(?:\[\])?\s+(g\w+)\s*=")
CONST_DEF = re.compile(r"^\s*(?:extern\s+)?const\s+\w+\s+(c\w+)\s*=")
EXTERN_DECL = re.compile(r"^\s*extern\s+[\w\[\]]+\s+(\w+)")
# Arithmetic on the left of a comparison, with no parenthesis before it.


def strip(text, keep_strings=False):
    """Blank out comments (and optionally strings) while preserving line numbers."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and nxt == "*":
            while i < n and not (text[i] == "*" and text[i + 1:i + 2] == "/"):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
        elif c == '"':
            out.append('"' if keep_strings else " ")
            i += 1
            while i < n and text[i] != '"':
                out.append(text[i] if keep_strings else ("\n" if text[i] == "\n" else " "))
                i += 1
            out.append('"' if keep_strings else " ")
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def check_balance(lines, report):
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for lineno, line in enumerate(lines, 1):
        for ch in line:
            if ch in "([{":
                stack.append((ch, lineno))
            elif ch in pairs:
                if not stack or stack[-1][0] != pairs[ch]:
                    report(lineno, f"unbalanced '{ch}'")
                    return
                stack.pop()
    for ch, lineno in stack:
        report(lineno, f"unclosed '{ch}'")


def check_switch(lines, report):
    for lineno, line in enumerate(lines):
        if CASE.match(line):
            rest = [l for l in lines[lineno + 1:] if l.strip()]
            if not rest or not (rest[0].strip().startswith("{") or CASE.match(rest[0])):
                report(lineno + 1, "case body must be a braced block")
        elif CASE_INLINE.match(line):
            report(lineno + 1, "put the case body in braces on its own lines")


def check_forward_refs(lines, report):
    defs = {}
    for i, line in enumerate(lines):
        m = FUNC_DEF.match(line)
        if m and not m.group(1):
            defs.setdefault(m.group(2), i)
    for i, line in enumerate(lines):
        for name in CALL.findall(line):
            if name in defs and name not in KEYWORDS and defs[name] > i:
                report(i + 1, f"'{name}' is used before it is defined")


def check_globals(lines, extern_globals, report):
    local = {m.group(1) for line in lines if (m := GLOBAL_DEF.match(line))}
    for i, line in enumerate(lines):
        for name in set(re.findall(r"\b(g[A-Z]\w*)\b", line)):
            if name not in local and name not in extern_globals:
                report(i + 1, f"'{name}' is not extern, so it is not visible here")


def check_constants(lines, known_constants, report):
    local = {m.group(1) for line in lines if (m := CONST_DEF.match(line))}
    for i, line in enumerate(lines):
        for name in set(re.findall(r"\b(c[A-Z]\w*)\b", line)):
            if name not in local and name not in known_constants:
                report(i + 1, f"'{name}' is not a known constant")


def check_functions(lines, known_functions, report):
    local = {m.group(2) for line in lines if (m := FUNC_DEF.match(line))}
    for i, line in enumerate(lines):
        for name in set(CALL.findall(line)):
            if name not in local and name not in known_functions and name not in KEYWORDS:
                report(i + 1, f"'{name}' is not a known function")


def check_rule_names(text, known_rules, report):
    for i, line in enumerate(text.splitlines(), 1):
        for name in RULE_USE.findall(line):
            if name not in known_rules:
                report(i, f"rule '{name}' is not defined anywhere")


def joined_lines(lines):
    """Yield (index, text) with lines that leave a '(' open joined to the next, so a
    condition split across lines is seen whole. The index is the first line's."""
    start, parts, depth = 0, [], 0
    for i, line in enumerate(lines):
        if not parts:
            start = i
        parts.append(line)
        depth += line.count("(") - line.count(")")
        if depth <= 0:
            yield start, " ".join(parts)
            parts, depth = [], 0
    if parts:
        yield start, " ".join(parts)


def check_left_arithmetic(lines, report):
    """A comparison whose left operand is arithmetic must be parenthesised inside a
    compound condition. Walks the tokens before each top-level comparison, skipping
    over parenthesised groups, looking for an unbracketed '*' or '/'."""
    token = re.compile(r">=|<=|==|!=|&&|\|\||[()\[\]]|[A-Za-z0-9_.]+|[*/+\-<>]")
    for i, line in joined_lines(lines):
        if "&&" not in line and "||" not in line:
            continue
        tokens = token.findall(line)
        for j, tok in enumerate(tokens):
            if tok not in (">", ">=", "<", "<=", "==", "!="):
                continue
            k, found = j - 1, False
            while k >= 0:
                if tokens[k] in ("&&", "||", "("):
                    break
                if tokens[k] == ")":
                    depth = 1
                    k -= 1
                    while k >= 0 and depth:
                        depth += (tokens[k] == ")") - (tokens[k] == "(")
                        k -= 1
                    continue
                if tokens[k] in ("*", "/"):
                    found = True
                    break
                k -= 1
            if found:
                report(i + 1, "parenthesise arithmetic on the left of a comparison (error 0308)")
                break


def game_symbols():
    extern_globals, constants, rules, functions = set(), set(), set(), set()
    if not GAME_AI.is_dir():
        return None
    for path in GAME_AI.rglob("*.xs"):
        text = strip(path.read_text(errors="ignore"))
        for line in text.splitlines():
            if m := EXTERN_DECL.match(line):
                extern_globals.add(m.group(1))
            if m := RULE_DEF.match(line):
                rules.add(m.group(1))
        # Engine constants (cMyID, cUnitType...) are never defined in XS, only used.
        constants |= set(re.findall(r"\b(c[A-Z]\w*)\b", text))
        # Syscalls are never defined in XS either; every call or definition counts.
        functions |= set(CALL.findall(text))
    if CONSTANTS.is_file():
        constants |= set(re.findall(r"\b(c[A-Z]\w*)\b", CONSTANTS.read_text(errors="ignore")))
    return extern_globals, constants, rules, functions


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    use_game = "--no-game" not in sys.argv
    targets = [Path(a) for a in args] or DEFAULT_TARGETS

    symbols = game_symbols() if use_game else None
    if use_game and symbols is None:
        print(f"game scripts not found at {GAME_AI}; run with --no-game to skip "
              f"symbol checks", file=sys.stderr)
        symbols = None

    failures = 0
    for target in targets:
        problems = []
        text = target.read_text()
        # Keep strings for rule names, blank them for everything structural.
        code = strip(text)
        lines = code.splitlines()
        keep = strip(text, keep_strings=True)

        check_balance(lines, lambda ln, msg: problems.append((ln, msg)))
        check_switch(lines, lambda ln, msg: problems.append((ln, msg)))
        check_forward_refs(lines, lambda ln, msg: problems.append((ln, msg)))
        check_left_arithmetic(lines, lambda ln, msg: problems.append((ln, msg)))
        if symbols:
            extern_globals, constants, rules, functions = symbols
            check_globals(lines, extern_globals, lambda ln, msg: problems.append((ln, msg)))
            check_constants(lines, constants, lambda ln, msg: problems.append((ln, msg)))
            check_functions(lines, functions, lambda ln, msg: problems.append((ln, msg)))
            check_rule_names(keep, rules | {m.group(1) for m in
                                            (RULE_DEF.match(l) for l in lines) if m},
                             lambda ln, msg: problems.append((ln, msg)))

        rel = target.relative_to(REPO) if REPO in target.parents else target
        if problems:
            failures += 1
            print(f"{rel}: {len(problems)} problem(s)")
            for lineno, msg in sorted(problems):
                print(f"  {rel}:{lineno}: {msg}")
        else:
            print(f"{rel}: OK")

    if not use_game:
        print("(symbol checks skipped: --no-game)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
