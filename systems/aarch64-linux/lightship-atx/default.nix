# /etc/nixos/hosts/lighthouse-east.nix
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

    # Call the function from your library, passing it the key path.
    # The impurity of getEnv is now handled cleanly at the call site.
    (lib.preseedSshKey (builtins.getEnv "HOST_SSH_KEY"))
  ];

  # Enable and configure the common hetzner module for this host
  ${namespace}.hosts.lightship = {
    enable = true;
    role = "server"; # This is the master node
    k8sServerAddr = "https://100.94.107.39:6443";
  };

  systemd.services.custom-leds = {
    description = "Custom LED Configuration";
    script = ''
      echo none > /sys/class/leds/user-led2/trigger
      echo none > /sys/class/leds/user-led1/trigger
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };

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
