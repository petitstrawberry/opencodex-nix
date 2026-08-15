#!/usr/bin/env python3
"""Normalize opencodex's root bun.lock for the hermetic Nix build.

Removes the bundled `bun` runtime dependency (the workspace dependency
entry, trustedDependencies, the `bun` package and the @oven/bun-* platform
binaries) so the Nix package can inject the nixpkgs `bun` instead.
Prints the normalized lockfile to stdout.

Usage: normalize-lock.py <path/to/bun.lock>
"""

import json
import re
import sys


def load(text: str) -> dict:
    # bun.lock v1 is JSON with trailing commas
    return json.loads(re.sub(r",\s*([}\]])", r"\1", text))


def main() -> None:
    src = sys.argv[1]
    lines = open(src, encoding="utf-8").read().split("\n")

    # 1) workspace dependency on the bundled bun runtime (8-space indent,
    #    inside workspaces."" .dependencies)
    for i, ln in enumerate(lines):
        if re.match(r'^        "bun": "', ln):
            assert ln.rstrip().endswith(","), ln
            lines[i] = None

    # 2) trustedDependencies block (contains only "bun")
    for i, ln in enumerate(lines):
        if ln == '  "trustedDependencies": [':
            assert lines[i + 1].strip() == '"bun",', lines[i + 1]
            assert lines[i + 2] == "  ],", lines[i + 2]
            lines[i : i + 3] = [None, None, None]

    # 3) the `bun` package entry and the @oven/bun-* platform packages
    for i, ln in enumerate(lines):
        if ln is None:
            continue
        if re.match(r'^    "@oven/bun-', ln) or ln.startswith('    "bun": ["bun@'):
            assert ln.rstrip().endswith("],"), ln
            lines[i] = None

    # collapse duplicate blank lines left by removals
    out: list[str] = []
    for ln in lines:
        if ln is None:
            continue
        if out and ln == "" and out[-1] == "":
            continue
        out.append(ln)
    while out and out[-1] == "":
        out.pop()

    text = "\n".join(out) + "\n"

    # sanity check: the textual result equals a programmatic normalization
    expected = load(open(src, encoding="utf-8").read())
    ws = expected["workspaces"][""]
    ws["dependencies"].pop("bun", None)
    expected.pop("trustedDependencies", None)
    expected["packages"].pop("bun", None)
    for k in list(expected["packages"]):
        if k.startswith("@oven/bun-"):
            del expected["packages"][k]
    assert load(text) == expected, "normalized lockfile does not match expected content"

    sys.stdout.write(text)


if __name__ == "__main__":
    main()
