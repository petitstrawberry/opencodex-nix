#!/usr/bin/env python3
"""Merge independently computed platform hashes into version.json."""

import json
import sys


def load(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: merge-platform-hashes.py "
            "<base-version.json> <linux-version.json> <darwin-version.json>"
        )

    base_path, linux_path, darwin_path = sys.argv[1:]
    base = load(base_path)
    platform_files = {
        "x86_64-linux": load(linux_path),
        "aarch64-darwin": load(darwin_path),
    }

    for platform, candidate in platform_files.items():
        for field in ("version", "srcHash"):
            if candidate[field] != base[field]:
                raise SystemExit(
                    f"{platform} {field} mismatch: "
                    f"{candidate[field]!r} != {base[field]!r}"
                )
        hash_ = candidate["bunDepsHash"].get(platform)
        if not isinstance(hash_, str) or not hash_.startswith("sha256-"):
            raise SystemExit(f"invalid {platform} bunDeps hash: {hash_!r}")
        base["bunDepsHash"][platform] = hash_

    with open(base_path, "w", encoding="utf-8") as f:
        json.dump(base, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
