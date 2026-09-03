{
  config,
  lib,
  pkgs,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.dgx-spark;
  sops = config.sops;

  # Build natively on the Spark itself (or on ARM infra) by setting
  # BUILD_ARM_NATIVE=true. Default: cross-compile the NVIDIA kernel on x86_64
  # (see ./cross-kernel.nix) so the infra can pre-build before hardware arrives.
  buildArmNative = builtins.getEnv "BUILD_ARM_NATIVE" == "true";

  # Reuse the exact component derivations from the vendor's NCCL dev shell.
  # This is important: that shell is built from the vendor's CUDA-fixed package
  # scope, where the invalid SBSA cuda_compat package is disabled.
  ncclShell =
    inputs.nixos-dgx-spark.devShells.${pkgs.stdenv.hostPlatform.system}.nccl-two-sparks;
  ncclShellPackages = ncclShell.nativeBuildInputs;
  ncclPackage = name:
    builtins.head (
      builtins.filter (package: (package.pname or package.name or "") == name)
        ncclShellPackages
    );
  perftest = ncclPackage "perftest";
  ncclNetSetup = ncclPackage "nccl-net-setup";
  ncclRdmaCheck = ncclPackage "nccl-rdma-check";
  ncclRun = ncclPackage "nccl-run";
  ncclRun16g = ncclPackage "nccl-run-16g";
in
{
  options.${namespace}.hosts.dgx-spark = {
    enable = mkBoolOpt false "Whether to enable the DGX Spark (GB10) base configuration";
    allFeatures = mkBoolOpt true "Whether to enable all features. Set to false for safe boot mode with minimal services.";
    enableK8s = mkBoolOpt true "Whether to provision and start the Kubernetes node";
    enableNvidiaContainerRuntime = mkBoolOpt false "Whether to enable the NVIDIA containerd runtime";
    dhcp = mkBoolOpt false "Use DHCP on the management interface instead of static addressing";
    ipAddress = mkOpt types.str "" "Main static management IP address with CIDR";
    vlanIpAddress = mkOpt types.str "" "Additional IP with CIDR for tagged VLAN on mgmnt interface";
    vlanId = mkOpt types.int 1 "VLAN ID for the tagged VLAN";
    interfaceMac = mkOpt types.str "" "MAC of the primary fabric (k3s/mgmt) NIC. The ConnectX-7 ports are the dedicated RDMA interconnect — the k3s fabric should be on the standard NIC (like astrolabe). Pin this once hardware arrives.";
    interfaceDriver = mkOpt types.str "" "Driver of the primary fabric NIC (e.g. r8125). Used as a fallback when interfaceMac is unset. NOTE: do not use mlx5_core here — those ports are the ConnectX interconnect, not the k3s fabric.";
    rdmaPeerManagementIp = mkOpt types.str ""
      "Management IP of the directly connected RDMA peer (for MPI bootstrap callbacks)";
    rdmaLinks = mkOption {
      default = [ ];
      description = "ConnectX/RoCE interfaces to configure as direct links";
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Kernel network interface name";
          };
          mac = mkOption {
            type = types.str;
            description = "Permanent ConnectX MAC address";
          };
          address = mkOption {
            type = types.str;
            description = "Direct-link IPv4 address with prefix";
          };
          peerAddress = mkOption {
            type = types.str;
            description = "Peer IPv4 address without prefix";
          };
          peerMac = mkOption {
            type = types.str;
            description = "Peer MAC address for a persistent neighbor entry";
          };
        };
      });
    };
    k8sNodeIp = mkOpt types.str "" "IP address for custom k8s node IP";
    k8sNodeIface = mkOpt types.str "" "Iface for k8s";
    k8sServerAddr =
      mkOpt types.str ""
        "Address of the server node to connect to (not needed for the first node).";
  };

  config = mkIf cfg.enable {
    # ------------------------------------------------------------------
    # NVIDIA DGX Spark hardware support (from nixos-dgx-spark flake):
    #   - custom NVIDIA 6.17 kernel built from NV-Kernels source (GB10)
    #   - nvidia open driver + modesetting + persistenced
    #   - podman + nvidia-container-toolkit
    #   - DGX dashboard (http://<host>:11000)
    #   - flox binary cache substituter for prebuilt CUDA packages
    # ------------------------------------------------------------------
    hardware.dgx-spark = {
      enable = true;
      useNvidiaKernel = true;
      cppcAutonomousMode = true;
    };

    # NVIDIA 6.17 kernel for GB10. Cross-compiled on x86_64 until the hardware
    # arrives (BUILD_ARM_NATIVE unset); self-hosted once the Sparks boot.
    boot.kernelPackages = mkIf (!buildArmNative) (
      mkOverride 40 (import ./cross-kernel.nix { inherit inputs lib; })
    );

    # nvidia-settings is an x86-oriented GTK control panel. Its 595.x build
    # hard-codes the Linux_x86_64 output directory and fails when cross-built
    # for the Spark, even though the driver itself builds correctly. The Spark
    # is headless, so do not include this optional GUI package.
    hardware.nvidia.nvidiaSettings = lib.mkForce false;

    # The upstream module scrubs kernel-dev store references from the built .ko
    # files against its own internal (native) kernel, which drags a QEMU-built
    # kernel into the closure when cross-compiling. Scrub against whichever
    # kernel is actually active instead — correct in both cross and native mode.
    hardware.nvidia.package = lib.mkForce (
      let
        prod = config.boot.kernelPackages.nvidiaPackages.production;
        scrubKernelDevRefs = drv:
          drv.overrideAttrs (old: {
            postFixup = (old.postFixup or "") + ''
              if [ -d "$out/lib/modules" ]; then
                find $out/lib/modules -name '*.ko' -print0 \
                  | xargs -0 -r ${pkgs.removeReferencesTo}/bin/remove-references-to \
                      -t ${config.boot.kernelPackages.kernel.dev}
              fi
            '';
          });
      in
      prod
      // {
        open = scrubKernelDevRefs prod.open;
        mod = scrubKernelDevRefs prod.mod;
      }
    );

    # DGX Spark baseline hardware config (from the reference template;
    # replace with `nixos-generate-config` output on first boot if needed)
    boot.initrd.availableKernelModules = [
      "nvme" # NVMe storage
      "usb_storage" # USB storage support
      "usbhid" # USB input devices
    ];

    # Cluster secrets — same k3s token as the other agents in the cluster.
    # TODO: once the hosts boot, add their ssh host keys to
    # modules/nixos/hosts/dgx-spark/secrets.enc.yaml recipients
    # (sops.age.sshKeyPaths = /etc/ssh/ssh_host_ed25519_key) and fill in the
    # real token with `sops edit`.
    sops.secrets.k8s_token = {
      sopsFile = ./secrets.enc.yaml;
    };

    # 802.1Q tagging for the mgmnt VLAN (same fabric as astrolabe)
    boot.kernelModules = [ "8021q" ];

    services.openssh = {
      enable = true;
      # Disable password-based authentication for security.
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false; # Disables keyboard-interactive auth, often a fallback for passwords.
        PermitRootLogin = "prohibit-password"; # Allows root login with a key, but not a password.
      };
    };

    environment.systemPackages = with pkgs; [
      python313Packages.huggingface-hub

      # ConnectX-7 RDMA/interconnect tooling. The upstream module already adds
      # rdma-core (libibverbs/librdmacm/ibv_devinfo), ethtool + unlimited memlock;
      # perftest (ib_write_bw/ib_read_bw) is NOT in nixpkgs so it comes from the
      # nixos-dgx-spark flake. The 200G QSFP link itself is addressed per-boot
      # with `nccl-net-setup` (vendor documents it as non-declarative).
      perftest
      ncclNetSetup
      ncclRdmaCheck
      ncclRun
      ncclRun16g
    ];

    ${namespace} = {

      system = {
        console-info.ip-display = enabled;
        nix-config = enabled;
      };

      suites = {
        loft = {
          enable = true;
          enableClient = true;
          enableServer = true;
        };
        monitoring = mkIf cfg.allFeatures {
          enable = true;
        };
      };

      services = {
        k8s = mkIf (cfg.allFeatures && cfg.enableK8s) {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = false;
          nodeIp = cfg.k8sNodeIp;
          nodeIface = cfg.k8sNodeIface;
          serverAddr = cfg.k8sServerAddr;
          networkType = "standard";
          role = "agent"; # Worker/Agent node
          enableNvidiaContainerRuntime = cfg.enableNvidiaContainerRuntime;
          extraArgs = [
            # kubectl derives the ROLES column from node-role.kubernetes.io/*.
            "--node-label=gpu-vendor=nvidia"
            "--node-label=gpu=dgx-spark"
            "--node-label=tier=compute"
          ];
        };
      };

      networking = {
        tailscale = mkIf cfg.allFeatures {
          enable = true;
          ephemeral = false;
          extraArgs = [
            "--accept-dns=false"
            "--accept-routes=false"
            "--advertise-routes="
            "--snat-subnet-routes=true"
          ];
        };
      };
    };

    # Traditional networking configuration (minimal)
    networking = {
      firewall = {
        allowedTCPPorts = [
          5201 # iperf
        ];
        # These are point-to-point QSFP links with no untrusted hosts between
        # the Sparks. RDMA/NCCL also uses dynamic ports during bootstrap.
        trustedInterfaces = builtins.map (link: link.name) cfg.rdmaLinks;

        # PRRTE advertises management first in its callback URI. Permit only
        # the peer Spark (rather than trusting the whole management LAN), or
        # the remote daemon stalls before trying the RDMA addresses.
        extraCommands = mkIf (
          cfg.rdmaPeerManagementIp != "" && !config.networking.nftables.enable
        ) ''
          iptables -w -C nixos-fw -s ${cfg.rdmaPeerManagementIp} -j nixos-fw-accept 2>/dev/null || \
            iptables -w -I nixos-fw 1 -s ${cfg.rdmaPeerManagementIp} -j nixos-fw-accept
        '';
        extraInputRules = mkIf (
          cfg.rdmaPeerManagementIp != "" && config.networking.nftables.enable
        ) ''
          ip saddr ${cfg.rdmaPeerManagementIp} accept comment "DGX Spark MPI peer"
        '';
      };
      # DHCP/static addressing is managed explicitly by systemd.network below.
      useDHCP = false;
      interfaces = {};
      nameservers = [
        "172.16.1.1"
        "1.1.1.1"
        "9.9.9.9"
      ];
      enableIPv6 = false;
      networkmanager.enable = false;
    };

    # systemd-networkd configuration — same pattern as astrolabe.
    # The primary fabric NIC is the standard 10GbE port (k3s + mgmnt, VLAN 10).
    # Each connected 200G QSFP port appears as two ConnectX/RoCE interfaces on
    # separate PCIe paths; both receive addresses and MTU 9000 for NCCL striping.
    systemd.network = {
      enable = true;

      # Only rename once we know which NIC the fabric is on (interfaceMac or
      # interfaceDriver); with neither set the link unit is skipped and the
      # machine boots with stock interface names.
      links."10-mgmnt" = mkIf (cfg.interfaceMac != "" || cfg.interfaceDriver != "") {
        matchConfig = if cfg.interfaceMac != "" then {
          PermanentMACAddress = cfg.interfaceMac;
        } else {
          Driver = cfg.interfaceDriver;
        };
        linkConfig.Name = "mgmnt";
      };

      netdevs."20-mgmnt-vlan" = mkIf (cfg.vlanIpAddress != "") {
        netdevConfig = {
          Name = "mgmnt.${toString cfg.vlanId}";
          Kind = "vlan";
        };
        vlanConfig = {
          Id = cfg.vlanId;
        };
      };

      networks = {
        "10-mgmnt-dhcp" = mkIf cfg.dhcp {
          matchConfig.Name = "mgmnt";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = "no";
          };
        };
        "11-mgmnt" = mkIf (!cfg.dhcp) {
          matchConfig = {
            Name = "mgmnt";
          };
          networkConfig = {
            DHCP = "no";
            Gateway = "172.16.1.1";
            IPv6AcceptRA = "no";
          };
          address = [
            "${cfg.ipAddress}"
          ];
          vlan = mkIf (cfg.vlanIpAddress != "") [ "mgmnt.${toString cfg.vlanId}" ];
          routes = [
            {
              Gateway = "172.16.1.1";
              Destination = "0.0.0.0/0";
            }
          ];
        };
        "21-mgmnt-vlan" = mkIf (!cfg.dhcp && cfg.vlanIpAddress != "") {
          matchConfig.Name = "mgmnt.${toString cfg.vlanId}";
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = "no";
          };
          linkConfig.MTUBytes = "9000";
          address = [ "${cfg.vlanIpAddress}" ];
        };
      } // builtins.listToAttrs (
        lib.imap0 (index: link:
          lib.nameValuePair "30-rdma-${toString index}" {
            matchConfig = {
              Name = link.name;
              PermanentMACAddress = link.mac;
            };
            networkConfig = {
              DHCP = "no";
              IPv6AcceptRA = "no";
              LinkLocalAddressing = "no";
            };
            linkConfig = {
              MTUBytes = "9000";
              RequiredForOnline = "no";
            };
            address = [ link.address ];
            # RoCE exhausts its retry budget too quickly to rely on cold ARP
            # resolution. A static neighbor makes the path immediately usable.
            neighbors = [
              {
                Address = link.peerAddress;
                LinkLayerAddress = link.peerMac;
              }
            ];
          }
        ) cfg.rdmaLinks
      );
    };

    # Both logical interfaces for one QSFP connector share an L2 segment.
    # Restrict ARP replies/announcements to the interface owning each address,
    # otherwise ARP flux can randomly collapse both subnets onto one path.
    systemd.services.dgx-spark-rdma-arp = mkIf (cfg.rdmaLinks != [ ]) {
      description = "Apply per-interface ARP policy for DGX Spark RoCE links";
      after = [ "systemd-networkd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatMapStringsSep "\n" (link: ''
        for attempt in $(seq 1 50); do
          [ -e "/proc/sys/net/ipv4/conf/${link.name}/arp_ignore" ] && break
          sleep 0.1
        done
        if [ ! -e "/proc/sys/net/ipv4/conf/${link.name}/arp_ignore" ]; then
          echo "ConnectX interface ${link.name} did not appear" >&2
          exit 1
        fi
        echo 1 > "/proc/sys/net/ipv4/conf/${link.name}/arp_ignore"
        echo 2 > "/proc/sys/net/ipv4/conf/${link.name}/arp_announce"
      '') cfg.rdmaLinks;
    };
  };
}
