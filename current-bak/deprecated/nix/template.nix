{ ssh-pub-keys, ... }:
{
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}:
{
  #enable proxmox lxc specific features

  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  boot.isContainer = true;
  system.stateVersion = "24.05";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    # require public key authentication
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "no";
    # settings.authorizedKeysFiles = [ ssh-pub-keys ];
  };

  # Set your time zone.
  time.timeZone = "America/Chicago";

  users.users.kpzak = {
    isNormalUser = true;
    home = "/home/kpzak";
    # initialPassword = "initchangeme";
    description = "default admin user";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [
      "${ssh-pub-keys}"
    ];
  };

  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Add authorized key from GitHub repository
  #users.users."root".openssh.authorizedKeys.keys
  # =
  #   let keys = import "${ssh-pub-keys}";
  #   in [ keys.root ];

  # users.users."root".openssh.authorizedKeys.keyFiles = [
  #  "${ssh-pub-keys}"
  # ];

  # Supress systemd units that don't work because of LXC
  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];

  # start tty0 on serial console
  systemd.services."getty@tty1" = {
    enable = lib.mkForce true;
    wantedBy = [ "getty.target" ]; # to start at boot
    serviceConfig.Restart = "always"; # restart when session is closed
  };

  environment.systemPackages = with pkgs; [
    bash
    helix
    binutils
  ];

}
