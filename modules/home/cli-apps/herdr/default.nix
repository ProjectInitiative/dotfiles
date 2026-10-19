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

  hasPlugins = cfg.plugins != { };

  # Script that installs any missing plugins
  pluginsScript = pkgs.writeShellScriptBin "herdr-plugins" ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" (
      map (name: ''
        # `herdr plugin list` prints ids as "- <id> (...)"; accept both that
        # and a bare "<id> ..." line so an installed plugin isn't reinstalled.
        if ! herdr plugin list 2>/dev/null | grep -qE "^(- )?${name} "; then
          echo "herdr: installing plugin ${name}..."
          herdr plugin install ${cfg.plugins.${name}.repo} --yes
        fi
      '') (attrNames cfg.plugins)
    )}
  '';
in
{
  options.${namespace}.cli-apps.herdr = with types; {
    enable = mkBoolOpt false "Whether to enable herdr terminal multiplexer configuration.";

    plugins = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkEnableOption "this herdr plugin";
            repo = mkOption {
              type = types.str;
              description = ''
                Source repo passed to `herdr plugin install`, in
                `owner/repo[/subdir]` form. `herdr plugin list` prints the
                attribute key (plugin id), but `install` requires the repo.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Herdr plugins to auto-install. Run herdr plugin list to see installed.
        Example:
        ```
        plugins."nikok6/herdr-mirror".enable = true;
        plugins."dcolinmorgan/herdr-remote".enable = true;
        ```
      '';
    };
  };

  config = mkIf cfg.enable {

    home.packages =
      with pkgs;
      [
        herdr
      ]
      ++ optional hasPlugins pluginsScript;

    home.file.".config/herdr/config.toml" = {
      source = "${inputs.self}/homes/dotfiles/herdr/config.toml";
    };

    # Auto-install plugins at login via a oneshot service
    systemd.user.services.herdr-plugins = mkIf hasPlugins {
      Unit = {
        Description = "Herdr plugin auto-installer";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${pluginsScript}/bin/herdr-plugins";
        RemainAfterExit = true;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };
}
