{ config, lib, pkgs, ... }:
let cfg = config.programs.receptor;
in {
  options.programs.receptor = {
    enable = lib.mkEnableOption "Receptor";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "Signed Receptor release package to install.";
    };
    migrateFromHomebrew = lib.mkEnableOption "the app-only, non-zap Homebrew transition";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { environment.systemPackages = [ cfg.package ]; }
    (lib.mkIf cfg.migrateFromHomebrew {
      assertions = [
        {
          assertion = config.homebrew.enable;
          message = "Receptor migration requires the Homebrew module.";
        }
        {
          assertion = !(lib.any (cask: lib.last (lib.splitString "/" cask.name) == "receptor") config.homebrew.casks);
          message = "Remove the Receptor cask declaration before enabling its Nix migration.";
        }
      ];
      system.activationScripts.homebrew.text = lib.mkBefore ''
        # A failed transition must abort before Homebrew's normal zap cleanup.
        /usr/bin/sudo --user=${lib.escapeShellArg config.homebrew.user} --set-home \
          /usr/bin/env PATH=${lib.makeBinPath [ pkgs.jq ]}:/usr/bin:/bin:/usr/sbin:/sbin \
          ${pkgs.bash}/bin/bash ${../scripts/migrate-homebrew.sh} \
          ${lib.escapeShellArg config.homebrew.prefix} || exit $?
      '';
    })
  ]);
}
