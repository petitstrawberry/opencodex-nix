#!/usr/bin/env bash
# Daily maintenance script for the opencodex package.
#
# - If a new upstream release exists: bump version, refresh the src hash and
#   regenerate the normalized bun.lock.
# - Always ensure the x86_64-linux bunDeps hash is present, computing it by
#   building the fixed-output dependency snapshot on this runner.
# - Finally verify the full package builds.
#
# Intended to run on an x86_64-linux GitHub Actions runner (ubuntu-latest).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PY="$(command -v python3)"

# --- latest upstream release ------------------------------------------------
LATEST_TAG="$(gh api repos/lidge-jun/opencodex/releases/latest --jq .tag_name)"
case "$LATEST_TAG" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "unexpected latest tag: $LATEST_TAG" >&2; exit 1 ;;
esac
VERSION="${LATEST_TAG#v}"

CURRENT="$("$PY" -c 'import json; print(json.load(open("version.json"))["version"])')"

if [[ "$VERSION" != "$CURRENT" ]]; then
  echo "Bumping opencodex $CURRENT -> $VERSION"

  TARBALL_URL="https://github.com/lidge-jun/opencodex/archive/refs/tags/${LATEST_TAG}.tar.gz"
  SRC_DIR="$(mktemp -d)"
  curl -fsSL "$TARBALL_URL" -o "$SRC_DIR/opencodex.tar.gz"

  # fetchFromGitHub (fetchzip) expects the hash of the unpacked tree
  SRC_BASE32="$(nix-prefetch-url --unpack --type sha256 "$TARBALL_URL" 2>/dev/null)"
  SRC_HASH="$(nix hash convert --hash-algo sha256 --to sri "$SRC_BASE32")"

  tar xzf "$SRC_DIR/opencodex.tar.gz" -C "$SRC_DIR"
  "$PY" "$PWD/scripts/normalize-lock.py" "$SRC_DIR/opencodex-${VERSION}/bun.lock" > bun.lock.normalized

  "$PY" - "$VERSION" "$SRC_HASH" <<'PY'
import json, sys
version, src_hash = sys.argv[1], sys.argv[2]
d = json.load(open("version.json"))
d["version"] = version
d["srcHash"] = src_hash
d["bunDepsHash"]["x86_64-linux"] = None
d["bunDepsHash"]["aarch64-darwin"] = None
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
fi

# --- ensure x86_64-linux bunDeps hash ---------------------------------------
LINUX_HASH="$("$PY" -c 'import json; print(json.load(open("version.json"))["bunDepsHash"]["x86_64-linux"])')"
if [[ -z "$LINUX_HASH" || "$LINUX_HASH" == "None" ]]; then
  echo "Computing x86_64-linux bunDeps hash..."
  "$PY" - <<'PY'
import json
d = json.load(open("version.json"))
d["bunDepsHash"]["x86_64-linux"] = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY

  OUT="$(nix build .#packages.x86_64-linux.opencodex --no-link 2>&1 || true)"
  GOT="$(printf '%s\n' "$OUT" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]\{10,\}\).*/\1/p' | tail -1)"
  if [[ -z "$GOT" ]]; then
    echo "could not obtain x86_64-linux bunDeps hash; build output:" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
  fi
  "$PY" - "$GOT" <<'PY'
import json, sys
d = json.load(open("version.json"))
d["bunDepsHash"]["x86_64-linux"] = sys.argv[1]
with open("version.json", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  echo "x86_64-linux bunDeps hash: $GOT"
fi

# --- final verification build ------------------------------------------------
nix build .#packages.x86_64-linux.opencodex --no-link

echo "done; version.json:"
cat version.json
