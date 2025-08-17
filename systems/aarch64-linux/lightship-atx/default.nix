{
  config,
  pkgs,
  inputs,
  namespace,
  modulesPath,
  lib,
  ...
}:
{
  imports = inputs.nixos-on-arm.bootModules.rock5a ++ [
    # Any additional modules you want to import
  ];

  # Enable and configure the common hetzner module for this host
  ${namespace}.hosts.lightship = {
    enable = false;
    role = "server"; # This is the master node
    k8sServerAddr = "https://100.94.107.39:6443";
  };
      # Enable and configure SSH, restricting access to public keys only
    services.openssh = {
      enable = true;
      # Disable password-based authentication for security.
      settings = {
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = true; # Disables keyboard-interactive auth, often a fallback for passwords.
        PermitRootLogin = "prohibit-password"; # Allows root login with a key, but not a password.
      };
    };


  # Filesystem configuration converted from fstab
  fileSystems = {
    # NVMe drive mount
    "/mnt/nvme/nvme-TEAM_TM8FP6512G_TPBF2502270050300037-part1" = {
      device = "/dev/disk/by-id/nvme-TEAM_TM8FP6512G_TPBF2502270050300037-part1";
      fsType = "ext4";
      options = [ 
        "rw"
        "noatime" 
        "nodiratime"
        "nofail"
      ];
    };

    # Bind mount for local provisioner
    "/mnt/local-provisioner" = {
      device = "/mnt/nvme/nvme-TEAM_TM8FP6512G_TPBF2502270050300037-part1";
      fsType = "none";
      options = [ 
        "bind"
        "nofail"
      ];
    };
  };

  # systemd.services.custom-leds = {
  #   description = "Custom LED Configuration";
  #   script = ''
  #     echo none > /sys/class/leds/blue\:status/trigger
      # echo none > /sys/class/leds/user-led1/trigger
  #   '';
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   wantedBy = [ "multi-user.target" ];
  # };

  # # Systemd service to set thermal governor (replaces /config/config.txt)
  # systemd.services.thermal-governor = {
  #   description = "Set Thermal Governor to power_allocator";
  #   script = ''
  #     echo power_allocator > /sys/devices/virtual/thermal/thermal_zone0/policy
  #   '';
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   wantedBy = [ "multi-user.target" ];
  # };

  system.stateVersion = lib.mkForce "25.05";

  # Load the watchdog kernel module
  # boot.kernelModules = [ "rockchip_wdt" ];

  # # Configure and enable the watchdog service
  # hardware.watchdog = {
  #   enable = true;
  #   device = "/dev/watchdog";
  #   interval = 10;
  #   interfaces = [ "tailscale0" ];
  #   # The original Ansible script used 'ansible_host' (the machine's own IP).
  #   # Pinging the machine itself can be a basic check that the network stack is up.
  #   # I am using the IP from k8sServerAddr as a placeholder.
  #   ping = [ "100.94.107.39" ];
  # };
}
