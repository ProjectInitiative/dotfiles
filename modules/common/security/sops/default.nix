{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.security.sops;
in
{
  options.${namespace}.security.sops = with types; {
    enable = mkBoolOpt false "Whether or not to enable common sops utilities.";
  };

  config = mkIf cfg.enable {

    environment.systemPackages = with pkgs; [
      age
      sops
    ];
  };
}
