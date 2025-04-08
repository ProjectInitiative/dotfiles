{
  lib,
  pkgs,
  inputs,
  namespace,
  system,
  config,
  options,
  ...
}:
with lib;
with lib.${namespace};
{
  imports = [
    # Include the docker hardware configuration
    ./hardware-configuration.nix
  ];

  # Docker-specific settings
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Nix garbage collection settings (similar to your ThinkPad)
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      persistent = true;
      options = "--delete-older-than 30d";
    };
    settings = {
      auto-optimise-store = true;
    };
    extraOptions = ''
      min-free = ${toString (100 * 1024 * 1024)}
      max-free = ${toString (512 * 1024 * 1024)}
    '';
  };

  home-manager.backupFileExtension = "backup";

  # Adapting your projectinitiative settings for Docker
  projectinitiative = {
    # encrypted.nix-signing = enabled;

    # Only include headless services, removing GUI components
    services = {
      # Removed power-profile-manager as it's not needed in Docker
    };

    suites = {
      development = enabled;
    };
    
    # Network configuration adapted for container
    networking = {
      tailscale = {
        enable = false;
        ephemeral = true;
        extraArgs = [ "--accept-routes" ];
      };
    };
  };

  # Enable basic networking
  networking.networkmanager.enable = true;

  # Container-specific packages
  environment.systemPackages = with pkgs; [
    # Development tools
  ];

  # Enable minimal services needed for development container
  services = {
    openssh = {
      enable = true;
      permitRootLogin = "no";
      passwordAuthentication = false;
    };
    
    # No need for printing, sound, display services in container
  };

  # Container users
  users.users.developer = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
  };


  # Keep the stateVersion the same as your ThinkPad for compatibility
  system.stateVersion = "24.05";
}
