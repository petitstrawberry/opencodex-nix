#!/usr/bin/env bash
# Compute and verify the bunDeps hash for one native platform.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PLATFORM="${1:?usage: update-platform.sh <platform>}"
case "$PLATFORM" in
  x86_64-linux|aarch64-darwin) ;;
  *) echo "unsupported automated-update platform: $PLATFORM" >&2; exit 1 ;;
esac

PY="$(command -v python3)"
CURRENT="$("$PY" -c "import json; print(json.load(open('version.json'))['bunDepsHash']['$PLATFORM'])")"

if [[ -n "$CURRENT" && "$CURRENT" != "None" ]]; then
  echo "$PLATFORM bunDeps hash already present: $CURRENT"
else
  echo "Computing $PLATFORM bunDeps hash..."

  # Build bunDeps as a normal derivation so its NAR hash can be read directly.
  # This one build needs network access for `bun install`.
  PATH_OUT="$(nix build \
    ".#packages.${PLATFORM}.opencodex.bunDeps" \
    --no-link \
    --print-out-paths \
    --option sandbox false)"
  HASH="$(nix path-info --json --json-format 1 "$PATH_OUT" | "$PY" -c \
    'import json,sys; d=json.load(sys.stdin); print(d[list(d)[0]]["narHash"])')"

  "$PY" - "$PLATFORM" "$HASH" <<'PY'
import json
import sys

platform, hash_ = sys.argv[1], sys.argv[2]
d = json.load(open("version.json"))
d["bunDepsHash"][platform] = hash_
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  echo "$PLATFORM bunDeps hash: $HASH"
fi

# Verify the complete package with the computed fixed-output hash.
nix build ".#packages.${PLATFORM}.opencodex" --no-link
