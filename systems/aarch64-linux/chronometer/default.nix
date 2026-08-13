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
  networking.hostName = "chronometer";

  # NVIDIA DGX Spark shared base module (kernels, drivers, k8s worker role).
  # Like astrolabe: mgmnt IP on the .1 subnet (via default_subnet), k8s fabric
  # on 172.16.4.x behind VLAN tag 10 on the same interface.
  # TODO: pin interfaceMac to the standard NIC once hardware arrives (the
  # ConnectX-7 ports are reserved for the RDMA interconnect, not k3s).
  ${namespace}.hosts.dgx-spark = {
    enable = true;
    ipAddress = "${config.sensitiveNotSecret.default_subnet}56/24";
    vlanIpAddress = "172.16.4.56/24";
    vlanId = 10;
    # interfaceMac = "TODO"; # standard NIC (not ConnectX) MAC
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
