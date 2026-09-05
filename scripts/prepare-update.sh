#!/usr/bin/env bash
# Prepare source metadata for the latest opencodex release.
#
# This step is platform-independent. Platform-specific bunDeps hashes are
# computed later, in parallel, by update-platform.sh.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PY="$(command -v python3)"

LATEST_TAG="$(gh api repos/lidge-jun/opencodex/releases/latest --jq .tag_name)"
case "$LATEST_TAG" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "unexpected latest tag: $LATEST_TAG" >&2; exit 1 ;;
esac
VERSION="${LATEST_TAG#v}"

CURRENT="$("$PY" -c 'import json; print(json.load(open("version.json"))["version"])')"
if [[ "$VERSION" == "$CURRENT" ]]; then
  echo "opencodex $CURRENT is already the latest release"
  exit 0
fi

echo "Preparing opencodex $CURRENT -> $VERSION"

TARBALL_URL="https://github.com/lidge-jun/opencodex/archive/refs/tags/${LATEST_TAG}.tar.gz"
SRC_DIR="$(mktemp -d)"
curl -fsSL "$TARBALL_URL" -o "$SRC_DIR/opencodex.tar.gz"

# fetchFromGitHub (fetchzip) expects the hash of the unpacked tree.
SRC_BASE32="$(nix-prefetch-url --unpack --type sha256 "$TARBALL_URL" 2>/dev/null)"
SRC_HASH="$(nix hash convert --hash-algo sha256 --to sri "$SRC_BASE32")"

tar xzf "$SRC_DIR/opencodex.tar.gz" -C "$SRC_DIR"
"$PY" "$PWD/scripts/normalize-lock.py" "$SRC_DIR/opencodex-${VERSION}/bun.lock" > bun.lock.normalized

"$PY" - "$VERSION" "$SRC_HASH" <<'PY'
import json
import sys

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
