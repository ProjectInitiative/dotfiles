{ pkgs ? import <nixpkgs> {} }:

let
  eval = pkgs.lib.evalModules {
    modules = [
      ../../modules/nixos/hosts/masthead/qos/default.nix
      {
        options.projectinitiative.hosts.masthead.enable = pkgs.lib.mkEnableOption "";
        options.projectinitiative.hosts.masthead.role = pkgs.lib.mkOption { type = pkgs.lib.types.str; };
        options.environment.systemPackages = pkgs.lib.mkOption { type = pkgs.lib.types.listOf pkgs.lib.types.package; };
        config.projectinitiative.hosts.masthead.enable = true;
        config.projectinitiative.hosts.masthead.role = "backup";
        config.projectinitiative.hosts.masthead.qos.enable = true;
      }
    ];
    specialArgs = {
      namespace = "projectinitiative";
      pkgs = pkgs;
      lib = pkgs.lib // {
        projectinitiative = {
          mkOpt = type: default: description: pkgs.lib.mkOption { inherit type default description; };
          mkBoolOpt = default: description: pkgs.lib.mkOption { type = pkgs.lib.types.bool; inherit default description; };
        };
      };
    };
  };
in
  eval.config.projectinitiative.hosts.masthead.qos.applyScript.outPath
