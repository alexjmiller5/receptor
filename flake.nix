{
  description = "Receptor signed macOS release";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          receptor = pkgs.callPackage ./nix/package.nix { };
          default = receptor;
        });
      darwinModules.default = import ./nix/module.nix;
      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          evaluate = settings: (nixpkgs.lib.evalModules {
            specialArgs = { inherit pkgs; };
            modules = [
              self.darwinModules.default
              ({ lib, ... }: {
                options = {
                  environment.systemPackages = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [ ];
                  };
                  assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ ]; };
                  homebrew = lib.mkOption { type = lib.types.attrs; default = {
                    enable = true; user = "test-user"; prefix = "/test-brew"; casks = [ ];
                  }; };
                  system.activationScripts.homebrew.text = lib.mkOption {
                    type = lib.types.lines; default = "";
                  };
                };
              })
              settings
            ];
          }).config;
          package = self.packages.${system}.receptor;
        in {
          inherit package;
          module = assert (evaluate { }).environment.systemPackages == [ ];
            assert (evaluate { programs.receptor.enable = true; }).system.activationScripts.homebrew.text == "";
            assert (evaluate { programs.receptor.enable = true; }).environment.systemPackages == [ package ];
            assert (evaluate {
              programs.receptor = { enable = true; package = pkgs.hello; };
            }).environment.systemPackages == [ pkgs.hello ];
            pkgs.runCommand "receptor-module-check" { } "touch $out";
        });
    };
}
