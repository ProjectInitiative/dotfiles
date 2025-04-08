# Hardware configuration for Docker container
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/docker.nix")
  ];

  # Container doesn't need most hardware-specific settings
  boot = {
    # Container doesn't need initrd and most boot settings
    isContainer = true;
    
    # Keep emulation support for cross-compilation like in your ThinkPad
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
        "armv7l-linux"
        "armv6l-linux"
      ];
    };
  };

  # Simplified file systems for container
  # fileSystems = {
  #   "/" = {
  #     device = "none";
  #     fsType = "tmpfs";
  #     options = [ "size=2G" "mode=755" ];
  #   };
    
  #   # Mount points for persistent storage
  #   "/data" = {
  #     device = "data";
  #     fsType = "none";
  #     options = [ "bind" ];
  #   };
    
  #   "/home" = {
  #     device = "home";
  #     fsType = "none";
  #     options = [ "bind" ];
  #   };
  # };

  # Container doesn't need swap
  swapDevices = [];

  # Network configuration simplified for container
  networking = {
    useDHCP = lib.mkDefault false;
    # Use container networking
    useHostResolvConf = true;
    # Container hostname
    hostName = "devcontainer";
  };

  # Container doesn't need microcode updates
  hardware = {
    enableRedistributableFirmware = false;
  };
}
