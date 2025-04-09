{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  inputs,
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.system.fonts;

  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment config
  isHomeManager = options ? home; # Home Manager always has home config
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
    enable = mkEnableOption "font management."; # Use standard mkEnableOption
    fonts = mkOption { type = listOf package; default = [ ]; description = "Custom font packages to install."; }; # Use standard mkOption
    linux = mkOption { type = bool; default = isLinux; description = "Is Linux system."; }; # Use standard mkOption
    darwin = mkOption { type = bool; default = isDarwin; description = "Is Darwin system."; }; # Use standard mkOption
    nixos = mkOption { type = bool; default = isNixOS; description = "Is NixOS system."; }; # Use standard mkOption
    homeManager = mkOption { type = bool; default = isHomeManager; description = "Is Home Manager context."; }; # Use standard mkOption
  };

  config = mkIf cfg.enable (
    # Base configuration that applies everywhere
    {
      # Your base config here
    }
    # NixOS-specific configuration
    // optionalAttrs isNixOS {
      environment.variables = {
        LOG_ICONS = "true";
      };
      environment.systemPackage =
        with pkgs;
        [

        ]
        ++ commonFonts;
    }
    # Linux-specific configuration (non-Home Manager)
    // optionalAttrs (isLinux && (!isHomeManager)) {
      environment.systemPackages = [ pkgs.font-manager ];
      fonts.packages = commonFonts;
    }
    # Darwin-specific configuration
    // optionalAttrs isDarwin {
      fonts = {
        fontDir.enable = true;
        fonts = commonFonts;
      };
    }
  );

  # config = mkIf cfg.enable (mkMerge [

  # common configurations
  # {
  #  fonts = mkIf (!isNixOS) {
  #     fontconfig = {
  #       defaultFonts = {
  #         emoji = [
  #           "hello"
  #         ];
  #       };
  #     };
  #  };
  # }

  # Environment variables for NixOS
  # (mkIf isNixOS {
  #   environment.variables = {
  #     LOG_ICONS = "true"; # Enable icons in tooling
  #   };
  # })

  # (mkIf (!isHomeManager) {
  #   environment.variables = {
  #     # Enable icons in tooling since we have nerdfonts.
  #     LOG_ICONS = "true";
  #   };
  # })

  # Linux-specific configuration
  # (mkIf (isLinux && (!isHomeManager)) {
  #   environment.systemPackages = [ pkgs.font-manager ];
  #   fonts.packages = commonFonts;
  # })

  # Darwin-specific configuration
  # (mkIf isDarwin {
  #   fonts = {
  #     fontDir = enabled;
  #     fonts = commonFonts;
  #   };
  # })
  # ]);

}
