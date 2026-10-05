{
  description = "WorkAdventure: collaborative virtual worlds";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        workadventure-messages = pkgs.callPackage ./nix/messages.nix {
          nodejs = pkgs.nodejs_24;
        };
        workadventure = pkgs.callPackage ./nix/package.nix {
          inherit workadventure-messages;
          nodejs = pkgs.nodejs_24;
        };
        default = workadventure;
      });

      apps = forAllSystems (
        pkgs:
        let
          wa = self.packages.${pkgs.stdenv.hostPlatform.system}.workadventure;
          app = name: {
            type = "app";
            program = "${wa}/bin/workadventure-${name}";
          };
        in
        {
          play = app "play";
          back = app "back";
          map-storage = app "map-storage";
          uploader = app "uploader";
          default = app "play";
        }
      );

      checks = forAllSystems (pkgs: {
        build = self.packages.${pkgs.stdenv.hostPlatform.system}.workadventure;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
