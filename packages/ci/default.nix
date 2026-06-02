{ inputs, pkgs, lib, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  systemConfigs = lib.filterAttrs (name: cfg: cfg.pkgs.stdenv.hostPlatform.system == system) inputs.self.nixosConfigurations;
  toplevels = lib.mapAttrsToList (name: cfg: {
    inherit name;
    path = cfg.config.system.build.toplevel;
  }) systemConfigs;
in
pkgs.linkFarm "ci" toplevels
