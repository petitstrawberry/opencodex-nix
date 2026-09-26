# opencodex-nix

Hermetic Nix packaging for [opencodex](https://opencodex.me/) — the universal
provider proxy for OpenAI Codex, Claude Code, Claude Desktop & Grok Build.

nixpkgs に opencodex パッケージはなく、プロジェクトも npm の
package-lock ではなく `bun.lock` しか配布していないため、このリポジトリで
hermetic なビルドを提供しています。バージョンとハッシュは
[version.json](./version.json) が唯一の情報源で、GitHub Actions が毎日
最新リリースを確認して `main` を自動更新します。

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
   bunDeps hash を並列の実ビルドで算出し、そのまま `nix build` で検証
4. 両方の結果をマージし、検証済みの状態で `main` に push
   (main が進んでいた場合は rebase して再試行)

更新内容を PR として残したい場合は `gh workflow run update -f mode=pr`。
その場合は `bot/opencodex-update` ブランチに push し、open 中の更新 PR を
更新 (なければ作成) したうえで auto-merge を有効化するため、こちらも人手は
不要です。main に必須チェックを設定していないので auto-merge は即座に
マージされます。`-f force=true` を付けるとバージョンが最新でも両プラット
フォームの hash を計算し直します。

検証は 3 の実ビルド (= ci.yml と同じビルド) で完了しているため、push 前に
別途 CI を待つ必要はありません。なお GitHub の仕様で `GITHUB_TOKEN` による
push は他ワークフローを起動しないため、自動更新後の main では ci.yml は
走りません。

手動バンプは `scripts/prepare-update.sh` を実行後、各プラットフォームで
`scripts/update-platform.sh <system>` を実行してください。

## Supported platforms

- aarch64-darwin / x86_64-darwin / aarch64-linux / x86_64-linux
- bunDeps hash は aarch64-darwin と x86_64-linux のみ CI で管理。他の
  platform は初回ビルド時にエラーが出た hash を `version.json` に埋めて
  ください。
