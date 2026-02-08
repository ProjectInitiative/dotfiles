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
  nvme = "nvme-Inland_TN320_NVMe_SSD_IB23AK0512P00800-part1";
in
{
  imports = inputs.nixos-on-arm.bootModules.rock5a ++ [
    # Any additional modules you want to import
  ];

  home-manager.backupFileExtension = "backup";

  ${namespace} = {

    # services.k8s.enable = lib.mkForce false;

    # Enable and configure the common hetzner module for this host
    hosts.lightship = {
      enable = true;
      role = "server"; # This is the master node
      k8sServerAddr = "https://100.92.52.46:6443";
      k3sDataDir = "/mnt/nvme/${nvme}/k3s";
    };
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

}
