#!/usr/bin/env bash
# Compute the aarch64-darwin bunDeps hash on an Apple Silicon runner.
# Runs only when the linux update job produced changes (see update.yml).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PY="$(command -v python3)"

ensure_hash() {
  local platform="$1"
  local current
  current="$("$PY" -c "import json; print(json.load(open('version.json'))['bunDepsHash']['$platform'])" )"
  if [[ -n "$current" && "$current" != "None" ]]; then
    echo "$platform bunDeps hash already present: $current"
    return 0
  fi

  echo "Computing $platform bunDeps hash..."
  local path
  path="$(nix build ".#packages.${platform}.opencodex.bunDeps" --no-link --print-out-paths --option sandbox false)"
  local hash
  hash="$(nix path-info --json --json-format 1 "$path" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); print(d[list(d)[0]]["narHash"])')"

  "$PY" - "$platform" "$hash" <<'PY'
import json, sys
platform, hash_ = sys.argv[1], sys.argv[2]
d = json.load(open("version.json"))
d["bunDepsHash"][platform] = hash_
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  echo "$platform bunDeps hash: $hash"
}

ensure_hash "aarch64-darwin"

# final verification build
nix build .#packages.aarch64-darwin.opencodex --no-link
