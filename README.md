# opencodex-nix

Hermetic Nix packaging for [opencodex](https://opencodex.me/) — the universal
provider proxy for OpenAI Codex, Claude Code, Claude Desktop & Grok Build.

nixpkgs に opencodex パッケージはなく、プロジェクトも npm の
package-lock ではなく `bun.lock` しか配布していないため、このリポジトリで
hermetic なビルドを提供しています。バージョンとハッシュは
[version.json](./version.json) が唯一の情報源で、GitHub Actions が毎日
最新リリースを確認して自動更新の PR を開きます。

## Usage

flake input として使い、overlay を適用します:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    opencodex-nix.url = "github:petitstrawberry/opencodex-nix";
  };

  outputs = { self, nixpkgs, opencodex-nix, ... }: {
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      modules = [
        { nixpkgs.overlays = [ opencodex-nix.overlays.default ]; }
      ];
      # ...
    };
  };
}
```

これで `pkgs.opencodex` (および `pkgs.ocx`) が使えます。直接ビルドする場合:

```sh
nix build .#packages.aarch64-darwin.opencodex
nix run .#packages.aarch64-darwin.opencodex
```

## How the package works

1. `bunDeps` — `bun install --frozen-lockfile` を一度だけ実行する
   fixed-output derivation (network 許可、fetchNpmDeps 相当)。root / gui の
   node_modules を store にスナップショットし、sandbox 内の本ビルドは
   network なしでそれを replay する。
2. npm の `bun` ランタイム依存は normalized `bun.lock` から除去し、
   nixpkgs の `bun` を注入 (`OPENCODEX_BUN_PATH`)。
3. CLI は公式 `bin/ocx.mjs` Node shim をラップしたもの。`ocx start` の
   SIGINT/SIGTERM 時の drain/restore は upstream 同様に動作する。

ランタイム状態 (`~/.opencodex`, `~/.codex`) はユーザー所有のままなので、
プロキシ本体だけが hermetic になります。

## Automatic updates

`.github/workflows/update.yml` が毎日 21:17 UTC (06:17 JST) に:

1. 最新リリース (`lidge-jun/opencodex`) を確認
2. 新バージョンがあれば src hash を再計算し、`bun.lock.normalized` を再生成
3. x86_64-linux (ubuntu runner) と aarch64-darwin (macos runner) の
   bunDeps hash を並列の実ビルドで算出
4. 両方の結果をマージし、`bot/opencodex-update` ブランチに1回だけ push
5. open 中の更新 PR があれば更新し、なければ新しい PR を開く

手動実行: `gh workflow run update`。手動バンプは
`scripts/prepare-update.sh` を実行後、各プラットフォームで
`scripts/update-platform.sh <system>` を実行してください。

## Supported platforms

- aarch64-darwin / x86_64-darwin / aarch64-linux / x86_64-linux
- bunDeps hash は aarch64-darwin と x86_64-linux のみ CI で管理。他の
  platform は初回ビルド時にエラーが出た hash を `version.json` に埋めて
  ください。
