{
  options,
  config,
  lib,
  pkgs,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.cli-apps.herdr;

  # Build list of plugins to auto-install on startup
  pluginsScript = pkgs.writeShellScriptBin "herdr-plugins" ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" (map (name: ''
      if ! herdr plugin list 2>/dev/null | grep -q "^${name} "; then
        echo "herdr: installing plugin ${name}..."
        herdr plugin install ${name} --yes
      fi
    '') (attrNames cfg.plugins))}
  '';
in
{
  options.${namespace}.cli-apps.herdr = with types; {
    enable = mkBoolOpt false "Whether to enable herdr terminal multiplexer configuration.";

    plugins = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this herdr plugin";
        };
      });
      default = { };
      description = ''
        Herdr plugins to auto-install. Run herdr plugin list to see installed.
        Example:
        ```
        plugins.herdr-mirror.enable = true;
        plugins.dcolinmorgan/herdr-remote.enable = true;
        ```
      '';
    };
  };

  config = mkIf cfg.enable {

    home.packages = with pkgs; [
      herdr
      pluginsScript
    ];

    home.file.".config/herdr/config.toml" = {
      source = "${inputs.self}/homes/dotfiles/herdr/config.toml";
    };

  };
}
