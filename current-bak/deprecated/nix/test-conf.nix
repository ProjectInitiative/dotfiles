# /etc/nixos/services/generate-config.nix

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  generateConfig = hostname: {
    # Define your dynamic configuration logic here
    # For example:
    networking.hostName = hostname;
    services.openssh.enable = (hostname == "storage1");
    # Add more configuration as needed...
  };
in
{
  options.services.generate-config = {
    enable = mkEnableOption "Enable the service to generate NixOS configuration dynamically";
  };

  config = mkIf (config.services.generate-config.enable) {
    systemd.services.generate-config = {
      description = "Generate NixOS configuration based on hostname";
      wantedBy = [ "multi-user.target" ];
      script = ''
        #!/bin/sh
        exec nixos-generate-config --root /mnt/nixos -o /mnt/nixos/configuration.nix
      '';
    };
  };
}
