{ config, pkgs, lib, modulesPath, ssh-pub-keys, ... }:

{
  # options.proxmoxLXC = {
  #   enable = lib.mkEnableOption "Enable Proxmox LXC specific configurations";
  # };

  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # config = lib.mkIf config.virtualisation.lxc.enable {
    boot.isContainer = true;
    system.stateVersion = "24.05";
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Enable SSH
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Set your time zone.
    time.timeZone = "America/Chicago";

    users.users.kylepzak = {
      isNormalUser = true;
      home = "/home/kylepzak";
      description = "default admin user";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keyFiles = [ ssh-pub-keys ];
    };

    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ];
      }
    ];

    # Suppress systemd units that don't work because of LXC
    systemd.suppressedSystemUnits = [
      "dev-mqueue.mount"
      "sys-kernel-debug.mount"
      "sys-fs-fuse-connections.mount"
    ];

    # Start tty0 on serial console
    systemd.services."getty@tty1" = {
      enable = lib.mkForce true;
      wantedBy = [ "getty.target" ];
      serviceConfig.Restart = "always";
    };

    environment.systemPackages = with pkgs; [
      bash
      helix
      binutils
      git
    ];
  # };
}
