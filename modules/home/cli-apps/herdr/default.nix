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
  cfg = config.${namespace}.cli-apps.herdr;
in
{
  options.${namespace}.cli-apps.herdr = with types; {
    enable = mkBoolOpt false "Whether to enable herdr terminal multiplexer configuration.";

    plugins = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this herdr plugin";
          source = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Compiled plugin package (.wasm file or derivation).";
          };
        };
      });
      default = { };
      description = "Herdr plugins to install.";
    };
  };

  config = mkIf cfg.enable {

    home.packages = with pkgs; [
      # herdr package
    ] ++ (builtins.filter (p: p != null) (
      map (name: cfg.plugins.${name}.source) (attrNames (filterAttrs (n: v: v.enable) cfg.plugins))
    ));

    # Plugin symlinks or config generation go here once we understand herdr's
    # plugin loading mechanism better.

  };
}
