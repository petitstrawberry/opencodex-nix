{
  description = "Hermetic Nix packaging for opencodex, the universal provider proxy (OpenAI Codex / Claude Code)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system}.extend self.overlays.default;
    in
    {
      overlays.default = import ./overlay.nix;

      packages = forAllSystems (system: {
        opencodex = (pkgsFor system).opencodex;
        default = (pkgsFor system).opencodex;
      });

      checks = forAllSystems (system: {
        opencodex = (pkgsFor system).opencodex;
      });
    };
}
