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
in
{
  networking.hostName = "sextant";

  # NVIDIA DGX Spark shared base module (kernels, drivers, k8s worker role).
  # Like astrolabe: mgmnt IP on the .1 subnet (via default_subnet), k8s fabric
  # on 172.16.4.x behind VLAN tag 10 on the same interface.
  # TODO: pin interfaceMac to the standard NIC once hardware arrives (the
  # ConnectX-7 ports are reserved for the RDMA interconnect, not k3s).
  ${namespace}.hosts.dgx-spark = {
    enable = true;
    # Production worker configuration: management on 172.16.1.0/24 and the
    # Kubernetes node/data path on VLAN 10 (172.16.4.0/24).
    allFeatures = true;
    enableK8s = true;
    enableNvidiaContainerRuntime = true;
    dhcp = false;
    ipAddress = "${config.sensitiveNotSecret.default_subnet}56/24";
    vlanIpAddress = "172.16.4.56/24";
    vlanId = 10;
    # Standard management NIC (enP7s7 / enP7p1s0), not ConnectX-7.
    interfaceMac = "30:c5:99:40:c4:2d";
    # One connected QSFP port exposes two 100G host paths. Keep them on
    # separate subnets so NCCL can stripe them without ARP flux.
    rdmaLinks = [
      {
        name = "enp1s0f1np1";
        mac = "30:c5:99:40:c4:2f";
        address = "172.16.5.56/24";
        peerAddress = "172.16.5.55";
        peerMac = "30:c5:99:40:fb:cf";
      }
      {
        name = "enP2p1s0f1np1";
        mac = "30:c5:99:40:c4:33";
        address = "172.16.6.56/24";
        peerAddress = "172.16.6.55";
        peerMac = "30:c5:99:40:fb:d3";
      }
    ];
    rdmaPeerManagementIp = "172.16.1.55";
    k8sServerAddr = "https://172.16.1.50:6443";
    k8sNodeIp = "172.16.4.56";
    k8sNodeIface = "mgmnt.10";
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
