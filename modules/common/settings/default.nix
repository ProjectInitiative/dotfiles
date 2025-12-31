{
  options, # All declared options in the system
  config, # Final evaluated configuration values
  pkgs,
  lib,
  namespace, # Your custom namespace, e.g., "mylib"
  osConfig ? null, # NixOS config, present when Home Manager is a NixOS module
  ...
}:

with lib;

let
  cfg = config.${namespace}.settings;

  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment config
  isHomeManager = options ? home; # Home Manager always has home config

in
{
  options.${namespace}.settings = {
    stateVersion = mkOption {
      type = types.str;
      default = "25.11";
      description = ''
        The state version for use within ${namespace} modules.
        Defaults to an inferred system or Home Manager stateVersion if possible.
      '';
    };

    # Option to control whether this module attempts to set system/home stateVersion
    manageGlobalSettings = mkOption {
      type = types.bool;
      default = true; # <<<<< IMPORTANT: Default to false for safety
      description = ''
        If true, this module will attempt to set system.stateVersion (for NixOS/nix-darwin)
        or home.stateVersion (for Home Manager) using the value of
        `${namespace}.stateVersion`. This uses lib.mkDefault, so it only applies
        if the respective stateVersion is not already set by the user or another module
        with higher priority.

        WARNING: Use with caution. It's generally better to set system.stateVersion
        and home.stateVersion explicitly in your main configuration files.
      '';
    };
  };

  config = lib.mkIf cfg.manageGlobalSettings (
    {

    }
    # Attempt to set system.stateVersion for NixOS or nix-darwin contexts
    # This condition applies if:
    # 1. `system.stateVersion` is a recognized option in the current evaluation (i.e., NixOS or nix-darwin context).
    # 2. `osConfig` is null. This distinguishes top-level NixOS/nix-darwin evaluations
    #    from Home Manager evaluations running as a NixOS module (where `osConfig` would be present).
    #    In the latter case, Home Manager shouldn't try to set the main system's stateVersion.
    // optionalAttrs (!isHomeManager) {
      security.sudo-rs.enable = true;
      system.stateVersion = lib.mkDefault cfg.stateVersion;
    }

    # Attempt to set home.stateVersion for Home Manager contexts
    # This condition applies if:
    # 1. `home.stateVersion` is a recognized option in the current evaluation (i.e., Home Manager context).
    # This will apply for both standalone Home Manager and Home Manager as a NixOS module.
    # // optionalAttrs isHomeManager {
    #   ${namespace}.home.stateVersion = lib.mkDefault cfg.stateVersion;
    #   # system.stateVersion = lib.mkDefault cfg.stateVersion;
    # }

  );
}
