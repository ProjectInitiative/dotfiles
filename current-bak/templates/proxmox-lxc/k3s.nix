{ config, lib, pkgs, ... }: {
  # https://kevingoos.medium.com/kubernetes-inside-proxmox-lxc-cce5c9927942

  # edit /etc/sysctl.conf on host
  # net.ipv4.ip_forward=1
  # vm.swapness=0
  
  # add to /etc/pve/nodes/NODE/lxc/NUM.conf
  # lxc.init.cmd: /sbin/init
  # lxc.apparmor.profile: unconfined
  # lxc.cgroup2.devices.allow: a
  # lxc.cap.drop:
  # lxc.mount.auto: "proc:rw sys:rw"

  # isMasterNode = hostName: hostName == "storage1";
  # Define the symlink creation script
  # symlinkScript = ''
  #   #!/bin/sh -e
  #   # Kubeadm 1.15 needs /dev/kmsg to be there, but it’s not in lxc, but we can just use /dev/console instead
  #   # see: https://github.com/kubernetes-sigs/kind/issues/662
  #   if [ ! -e /dev/kmsg ]; then
  #   ln -s /dev/console /dev/kmsg
  #   fi
  #   # https://medium.com/@kvaps/run-kubernetes-in-lxc-container-f04aa94b6c9c
  #   mount --make-rshared /
  # '';

  # Create a systemd service to run the symlink creation script
  systemd.services.createSymlink = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c \'if [ ! -e /dev/kmsg ]; then ln -s /dev/console /dev/kmsg; fi\'";
    };
  };

#   networking = {
#     interfaces = {
#       eth0.ipv4.addresses = [{
#         address = "172.16.1.180";
#         prefixLength = 24;
#       }];
#     };
#     defaultGateway = {
#       address = "172.16.1.1";
#       interface = "eth0";
#     };
# };


  networking.firewall.allowedTCPPorts = [
    6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
    2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
    2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # k3s, flannel: required if using multi-node for inter-node networking
  ];

  boot.extraModulePackages = [ config.boot.kernelPackages.wireguard ];
  environment.systemPackages = with pkgs; [
    k3s
    wireguard-go
    wireguard-tools
    fio
  ];

  services.k3s = {
    enable = true;
    role = "server";
    token = "ffv1y34np81u8t4vnzdwfmk";
    extraFlags = toString [
      "--secrets-encryption"
      "--flannel-backend vxlan"
    ];
    clusterInit = true;
  };
  # https://kevingoos.medium.com/kubernetes-inside-proxmox-lxc-cce5c9927942


#   postBoot = with pkgs.lib; let
#     isMaster = isMasterNode hostName;
#     in mkIf isMaster (
#       # Configuration for master node, e.g., include cluster-init
#       service.k3s.clusterInit = true;
#     ) ++ mkIf (!isMaster) (
#       # Configuration for worker nodes
#     );
}

# "--flannel-iface tailscale0"

# sample config
# #lxc.mount.auto%3A "sys%3Arw proc%3Arw"
# #lxc.cap.drop%3A
# #lxc.apparmor.profile%3A unconfined
# arch: amd64
# cores: 4
# features: fuse=1,nesting=1
# hostname: CT999
# memory: 4096
# mp0: /mnt/merged/nvme,mp=/mnt/merged/nvme
# mp1: /mnt/merged/ssd,mp=/mnt/merged/ssd
# mp2: /mnt/merged/hdd,mp=/mnt/merged/hdd
# net0: name=eth0,bridge=vmbr4,firewall=1,gw=172.16.1.1,hwaddr=BC:24:11:7C:D8:24,ip=172.16.4.71/24,type=veth
# ostype: nixos
# rootfs: local:999/vm-999-disk-0.raw,size=8G
# swap: 0
# lxc.init.cmd: /sbin/init
# lxc.cgroup.devices.allow: a
