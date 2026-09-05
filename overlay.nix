# opencodex — hermetic package overlay
#
# Wires `pkgs.opencodex` so opencodex can be installed declaratively
# (home-manager / nix-darwin / NixOS package lists).
#
# Why a custom package instead of a one-liner:
#   - nixpkgs has no `opencodex` package and no stable `buildBunPackage` yet.
#   - The project ships only `bun.lock` (not npm's package-lock.json), so
#     `buildNpmPackage` is unusable.
#
# How it works:
#   1. `bunDeps` — a fixed-output derivation that runs `bun install
#      --frozen-lockfile` ONCE (network allowed, like fetchNpmDeps) and
#      snapshots the resulting node_modules (root + gui) into the store.
#      The sandboxed main build replays those, so the build itself never
#      touches the network.
#   2. The `bun` npm dependency (the runtime the npm launcher bundles) is
#      dropped via a normalized `bun.lock` (see bun.lock.normalized) so we
#      can inject the nixpkgs `bun` instead. No platform binary download
#      inside the sandbox.
#   3. The CLI is the official `bin/ocx.mjs` Node shim, wrapped with
#      `OPENCODEX_BUN_PATH=${bun}/bin/bun`. The shim forwards signals to the
#      Bun child so `ocx start` drains/restores on SIGINT/SIGTERM just like
#      upstream.
#
# Runtime state stays in ~/.opencodex and ~/.codex (mutable, user-owned) —
# only the program itself is hermetic, the right trade-off for a long-running
# local proxy.
#
# --- Hash maintenance on bump ---
# version.json is the single source of truth for version/srcHash/bunDepsHash.
# The GitHub Actions workflow (`.github/workflows/update.yml`) refreshes it
# daily and opens a PR. To bump manually:
#   1. edit version.json (version + srcHash; null out bunDepsHash)
#   2. regenerate bun.lock.normalized: scripts/normalize-lock.py <upstream bun.lock>
#   3. build once per platform and copy the "got: sha256-..." hash into
#      version.json (or run scripts/update.sh on the platform)

final: prev:
let
  inherit (final.stdenv.hostPlatform) system;
  inherit (final.lib) makeBinPath;

  meta = builtins.fromJSON (builtins.readFile ./version.json);

  pname = "opencodex";
  version = meta.version;

  src = final.fetchFromGitHub {
    owner = "lidge-jun";
    repo = "opencodex";
    rev = "v${version}";
    hash = meta.srcHash;
  };

  # Lockfile with the bundled `bun` runtime dependency removed.
  normalizedBunLock = ./bun.lock.normalized;

  # The nixpkgs `bun` to inject (project pins bun 1.3.x — patch-compatible).
  bun = prev.bun;

  # Per-platform snapshot of `bun install --frozen-lockfile` node_modules
  # (root + gui). Platform-specific because @napi-rs/keyring installs a
  # per-OS binary.
  bunDepsHash = meta.bunDepsHash;

  bunDeps = final.runCommand "${pname}-${version}-bun-deps" {
    nativeBuildInputs = [ bun ];
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = bunDepsHash.${system} or null;
    impureEnvVars = final.lib.fetchers.proxyImpureEnvVars;
    preferLocalBuild = true;
  } ''
    export HOME=$TMPDIR
    mkdir -p build
    cp -a ${src}/. build/
    chmod -R u+w build
    ${prev.python3}/bin/python3 - <<'PY'
import json
p = "build/package.json"
d = json.load(open(p))
d["dependencies"].pop("bun", None)
d["trustedDependencies"] = [t for t in d.get("trustedDependencies", []) if t != "bun"]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
    cp ${normalizedBunLock} build/bun.lock
    cd build
    bun install --frozen-lockfile --backend=copy
    mkdir -p $out/root
    cp -a node_modules/. $out/root/
    cd gui
    bun install --frozen-lockfile --backend=copy
    mkdir -p $out/gui
    cp -a node_modules/. $out/gui/
  '';
in
{
  opencodex =
    (prev.stdenv.mkDerivation {
      inherit pname version src;

      nativeBuildInputs = [ bun prev.python3 prev.makeWrapper ];
      buildInputs = [ prev.nodejs ];

      patchPhase = ''
        ${prev.python3}/bin/python3 - <<'PY'
import json
p = "package.json"
d = json.load(open(p))
d["dependencies"].pop("bun", None)
d["trustedDependencies"] = [t for t in d.get("trustedDependencies", []) if t != "bun"]
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
        cp -a ${bunDeps}/root ./node_modules
        cp -a ${bunDeps}/gui ./gui/node_modules
        chmod -R u+w node_modules gui/node_modules
        patchShebangs node_modules gui/node_modules
      '';

      buildPhase = ''
        runHook preBuild
        ( cd gui && bun run build )
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib/opencodex $out/lib/opencodex/gui $out/bin
        cp -a bin src package.json $out/lib/opencodex/
        mkdir -p $out/lib/opencodex/gui
        cp -a gui/dist $out/lib/opencodex/gui/dist
        cp -a node_modules $out/lib/opencodex/node_modules
        makeWrapper ${prev.nodejs}/bin/node $out/bin/ocx \
          --add-flags "$out/lib/opencodex/bin/ocx.mjs" \
          --set OPENCODEX_BUN_PATH ${bun}/bin/bun \
          --prefix PATH : ${makeBinPath [ prev.nodejs bun ]}
        ln -s ocx $out/bin/opencodex
        runHook postInstall
      '';

      meta = {
        description = "Universal provider proxy for OpenAI Codex, Claude Code, Claude Desktop & Grok Build";
        homepage = "https://opencodex.me/";
        license = prev.lib.licenses.mit;
        mainProgram = "ocx";
        platforms = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      };
    })
    // { inherit bunDeps; };
}
