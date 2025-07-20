{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  # Define a shorthand for the configuration options of this module
  cfg = config.${namespace}.services.tpm;
in
{
  # Define the options that users can configure
  options.${namespace}.services.tpm = {
    enable = mkEnableOption "Trusted Platform Module (TPM) 2.0 support";
  };

  # Define the actual system configuration based on the options
  config = mkIf cfg.enable {

    users.groups.tss = {
      gid = 959; # A static GID from the system range
    };

    # Based on: https://nixos.wiki/wiki/TPM
    # Install specified TPM-related packages into the system profile
    environment.systemPackages = with pkgs; [
      opensc
      tpm2-tools
      tpm2-pkcs11
    ];

    security = {
      # Conditionally enable rtkit based on the module's option
      rtkit.enable = true;

      # Configure NixOS's built-in tpm2 support
      tpm2 = {
        enable = true; # This is the master switch for the NixOS tpm2 options
        pkcs11.enable = true;
        tctiEnvironment.enable = true;
      };
    };
  };
}
