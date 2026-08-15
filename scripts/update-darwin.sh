#!/usr/bin/env bash
# Compute the aarch64-darwin bunDeps hash on an Apple Silicon runner.
# Runs only when the linux update job produced changes (see update.yml).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PY="$(command -v python3)"

DARWIN_HASH="$("$PY" -c 'import json; print(json.load(open("version.json"))["bunDepsHash"]["aarch64-darwin"])')"
if [[ -n "$DARWIN_HASH" && "$DARWIN_HASH" != "None" ]]; then
  echo "aarch64-darwin hash already present: $DARWIN_HASH"
  exit 0
fi

echo "Computing aarch64-darwin bunDeps hash..."
"$PY" - <<'PY'
import json
d = json.load(open("version.json"))
d["bunDepsHash"]["aarch64-darwin"] = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY

OUT="$(nix build .#packages.aarch64-darwin.opencodex --no-link 2>&1 || true)"
GOT="$(printf '%s\n' "$OUT" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]\{10,\}\).*/\1/p' | tail -1)"
if [[ -z "$GOT" ]]; then
  echo "could not obtain aarch64-darwin bunDeps hash; build output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi
"$PY" - "$GOT" <<'PY'
import json, sys
d = json.load(open("version.json"))
d["bunDepsHash"]["aarch64-darwin"] = sys.argv[1]
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY

# final verification build
nix build .#packages.aarch64-darwin.opencodex --no-link
echo "aarch64-darwin bunDeps hash: $GOT"
