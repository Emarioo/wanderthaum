#!/usr/bin/env python3

import argparse
import re
from pathlib import Path


ROUTINE_PATTERN = re.compile(
    r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*::\s*proc\b"
)


def find_matching_paren(source, start):
    depth = 0
    i = start
    in_string = False
    in_raw_string = False
    in_line_comment = False
    in_block_comment = False

    while i < len(source):
        c = source[i]
        n = source[i + 1] if i + 1 < len(source) else ""

        if in_line_comment:
            if c == "\n":
                in_line_comment = False

        elif in_block_comment:
            if c == "*" and n == "/":
                in_block_comment = False
                i += 1

        elif in_string:
            if c == "\\":
                i += 1
            elif c == '"':
                in_string = False

        elif in_raw_string:
            if c == "`":
                in_raw_string = False

        elif c == "/" and n == "/":
            in_line_comment = True
            i += 1

        elif c == "/" and n == "*":
            in_block_comment = True
            i += 1

        elif c == '"':
            in_string = True

        elif c == "`":
            in_raw_string = True

        elif c == "(":
            depth += 1

        elif c == ")":
            depth -= 1
            if depth == 0:
                return i

        i += 1

    return -1


def split_parameters(source):
    parameters = []
    start = 0

    depths = {"(": 0, "[": 0, "{": 0}
    in_string = False
    in_raw_string = False
    in_line_comment = False
    in_block_comment = False

    i = 0

    while i < len(source):
        c = source[i]
        n = source[i + 1] if i + 1 < len(source) else ""

        if in_line_comment:
            if c == "\n":
                in_line_comment = False

        elif in_block_comment:
            if c == "*" and n == "/":
                in_block_comment = False
                i += 1

        elif in_string:
            if c == "\\":
                i += 1
            elif c == '"':
                in_string = False

        elif in_raw_string:
            if c == "`":
                in_raw_string = False

        elif c == "/" and n == "/":
            in_line_comment = True
            i += 1

        elif c == "/" and n == "*":
            in_block_comment = True
            i += 1

        elif c == '"':
            in_string = True

        elif c == "`":
            in_raw_string = True

        elif c in depths:
            depths[c] += 1

        elif c == ")":
            depths["("] -= 1

        elif c == "]":
            depths["["] -= 1

        elif c == "}":
            depths["{"] -= 1

        elif c == "," and all(v == 0 for v in depths.values()):
            part = source[start:i].strip()
            if part:
                parameters.append(part)
            start = i + 1

        i += 1

    remaining = source[start:].strip()
    if remaining:
        parameters.append(remaining)

    return parameters


def find_routines(path):
    source = path.read_text(encoding="utf-8", errors="replace")

    for match in ROUTINE_PATTERN.finditer(source):
        name = match.group(1)

        proc_start = match.end()
        paren_start = source.find("(", proc_start)

        if paren_start == -1:
            continue

        paren_end = find_matching_paren(source, paren_start)

        if paren_end == -1:
            continue

        params_source = source[paren_start + 1:paren_end]
        params = split_parameters(params_source)

        line = source.count("\n", 0, match.start()) + 1

        yield name, line, params


def main():
    parser = argparse.ArgumentParser(
        description="List Odin procedures and their parameters."
    )

    parser.add_argument(
        "directory",
        nargs="?",
        default=".",
        help="Source directory (default: current directory)"
    )

    parser.add_argument(
        "--exclude",
        action="append",
        default=["vendor", ".git"],
        help="Directory names to exclude"
    )

    args = parser.parse_args()
    root = Path(args.directory)

    files = sorted(
        path for path in root.rglob("*.odin")
        if not any(part in args.exclude for part in path.parts)
    )

    routines = []

    for path in files:
        for name, line, params in find_routines(path):
            routines.append((path, line, name, params))

    for path, line, name, params in routines:
        try:
            relative = path.relative_to(root)
        except ValueError:
            relative = path

        # print(f"\n{relative}:{line}")
        print(f"{name} :: proc(", end='')

        if params:
            for param in params:
                print(f"{param}, ", end='')
        # else:
        #     print("      // no parameters")

        print(")")

    print(f"\nFound {len(routines)} routines in {len(files)} files.")


if __name__ == "__main__":
    main()
