{
  config,
  pkgs,
  inputs,
  namespace,
  modulesPath,
  lib,
  ...
}:
let
  nvme = "nvme-TEAM_TM8FP6512G_TPBF2502270050301172-part1";
in
{
  imports = inputs.nixos-on-arm.bootModules.rock5a ++ [
    # Any additional modules you want to import
  ];

  home-manager.backupFileExtension = "backup";

  # Enable and configure the common hetzner module for this host
  ${namespace}.hosts.lightship = {
    enable = true;
    role = "server"; # This is the master node
    k8sServerAddr = "https://100.94.107.39:6443";
  };

  # Filesystem configuration converted from fstab
  fileSystems = {
    # NVMe drive mount
    "/mnt/nvme/${nvme}" = {
      device = "/dev/disk/by-id/${nvme}";
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
      device = "/mnt/nvme/${nvme}";
      fsType = "none";
      options = [ 
        "bind"
        "nofail"
      ];
    };
  };

  system.stateVersion = lib.mkForce "25.05";

}
