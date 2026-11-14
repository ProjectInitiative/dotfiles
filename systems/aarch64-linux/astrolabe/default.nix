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
  # TODO: pin interfaceMac to the new host's standard NIC once hardware
  # arrives (the ConnectX-7 ports are reserved for the RDMA interconnect,
  # not k3s). The mgmnt link rename is skipped until this is set — the
  # machine boots with stock interface names and DHCP until then.
  #
  # TODO: RDMA — chronometer/sextant/octant form a full switchless mesh and
  # both QSFP ports per node are already cabled. Cabling a 4th node requires
  # either re-plumbing the mesh or an RDMA switch; leave rdmaLinks empty and
  # extend modules/nixos/hosts/dgx-spark/topology.nix once the fabric is
  # decided. rdmaPeerManagementIps below keeps the node registered with the
  # existing mesh peers for ARP/inventory.
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
    interfaceMac = "";
    # No RDMA links yet — see TODO above.
    rdmaLinks = [ ];
    rdmaPeerManagementIps = [
      "172.16.1.55" # Chronometer
      "172.16.1.56" # Sextant
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
