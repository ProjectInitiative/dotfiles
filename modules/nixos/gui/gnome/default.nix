{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.gui.gnome;
  xorg = config.${namespace}.gui.display-server.xorg;
  wayland = config.${namespace}.gui.display-server.wayland;
in
{
  options.${namespace}.gui.gnome = with types; {
    enable = mkBoolOpt false "Whether or not to enable gnome desktop environment";
  };

  config = mkIf cfg.enable {

    # Enable the GNOME Desktop Environment
    services = {
      xserver = {
        enable = true;

        displayManager = {
          gdm = {
            enable = true;
            wayland = mkIf xorg.enable false;
          };
        };

        desktopManager = {
          gnome = {
            enable = true;
            extraGSettingsOverrides = ''
              [org.gnome.mutter]
              edge-tiling=true
              [org.gnome.desktop.wm.preferences]
              button-layout=':minimize,maximize,close'
            '';
          };
        };

      };
    };

    services.fwupd.enable = true;
    # Enable GNOME Shell extensions for all users
    environment = {

      sessionVariables = {
        GNOME_SHELL_EXTENSIONS = with pkgs.gnomeExtensions; [
          "${dash-to-dock}/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com"
          "${pop-shell}/share/gnome-shell/extensions/pop-shell@system76.com"
        ];
      };

      # System-wide gnome packages
      systemPackages = with pkgs; [
        gnome-firmware
        gnome-network-displays
        gnome-tweaks
        # gnomeExtensions.another-window-session-manager
        gnomeExtensions.appindicator
        gnomeExtensions.dash-to-dock
        gnomeExtensions.pop-shell
        gnomeExtensions.quake-terminal
      ];

    };

  };

}
