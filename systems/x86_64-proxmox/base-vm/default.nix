{ config, lib, pkgs, ... }:
{
  imports = [ ];
  
  # Basic system configuration
  system.stateVersion = "23.11";

  # Enable displaying network info on console
  services.getty.helpLine = lib.mkForce ''
    IP addresses:
    ${lib.concatMapStrings (i: ''
      - ${i.name}: \4{${i.name}}
    '') (lib.attrValues config.networking.interfaces)}
  '';

  networking.networkmanager.enable = true;
  
  # Add your other configuration options here
  services.openssh.enable = true;
  users.users.root.password = "changeme";  # Remember to change this
  programs.zsh.enable = true;
}
