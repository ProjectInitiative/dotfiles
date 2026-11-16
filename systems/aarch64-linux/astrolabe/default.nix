{
  config,
  pkgs,
  inputs,
  namespace,
  lib,
  ...
}:
let
  # DGX Spark 4TB NVMe
  rootDiskDevicePath = "/dev/nvme0n1";
  rdmaTopology = import ../../../modules/nixos/hosts/dgx-spark/topology.nix { inherit lib; };
in
{
  networking.hostName = "astrolabe";

  # NVIDIA DGX Spark shared base module (kernels, drivers, k8s worker role).
  # Reuses the old x86 Strix Halo astrolabe's name and .54 management IP.
  # Configuration mirrors chronometer/sextant/octant.
  #
  # RDMA: 4-node switchless ring (astrolabe → octant → chronometer →
  # sextant → astrolabe) declared once in
  # modules/nixos/hosts/dgx-spark/topology.nix.
  ${namespace}.hosts.dgx-spark = {
    enable = true;
    # Management on 172.16.1.0/24 and the Kubernetes node/data path on VLAN 10
    # (172.16.4.0/24).
    allFeatures = true;
    enableK8s = true;
    enableNvidiaContainerRuntime = true;
    dhcp = false;
    ipAddress = "${config.sensitiveNotSecret.default_subnet}54/24";
    vlanIpAddress = "172.16.4.54/24";
    vlanId = 10;
    # Standard management NIC (enP7s7 / enP7p1s0), not ConnectX-7.
    interfaceMac = "30:c5:99:40:35:05";
    rdmaLinks = rdmaTopology.linksFor config.networking.hostName;
    rdmaPeerManagementIps = [
      "172.16.1.55" # Chronometer
      "172.16.1.57" # Octant
    ];
    rdmaPeerControlIps = [ ];
    k8sServerAddr = "https://172.16.1.50:6443";
    k8sNodeIp = "172.16.4.54";
    k8sNodeIface = "mgmnt.10";
    gpuClockLimit = {
      enable = true;
      maxClock = 2200;
    };
  };

  # Disko layout — DGX Spark reference layout: ESP + swap + ext4 root
  disko.devices.disk.main = {
    device = rootDiskDevicePath;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        swap = {
          size = "2G";
          content = {
            type = "swap";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  system.stateVersion = "26.05";
}
