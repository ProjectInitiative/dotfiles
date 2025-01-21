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
  cfg = config.${namespace}.system.fonts;
  # Common font list for both platforms
  commonFonts =
    with pkgs;
    [
      fira-code
      fira-code-symbols
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      (nerdfonts.override { fonts = [ "Hack" ]; })
    ]
    ++ cfg.fonts;
in
{
  options.${namespace}.system.fonts = with types; {
    enable = mkBoolOpt false "Whether or not to manage fonts.";
    fonts = mkOpt (listOf package) [ ] "Custom font packages to install.";
  };

  config = mkIf cfg.enable (mkMerge [

    # common configurations
    {
      environment.variables = {
        # Enable icons in tooling since we have nerdfonts.
        LOG_ICONS = "true";
      };
    }

    # Linux-specific configuration
    (mkIf pkgs.stdenv.isLinux {
      environment.systemPackages = [ pkgs.font-manager ];
      fonts.packages = commonFonts;
    })

    # Darwin-specific configuration
    (mkIf pkgs.stdenv.isDarwin {
      fonts = {
        fontDir = enabled;
        fonts = commonFonts;
      };
    })
  ]);

}
