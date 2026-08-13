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
in
{
  options.${namespace}.hosts.dgx-spark = {
    enable = mkBoolOpt false "Whether to enable the DGX Spark (GB10) base configuration";
    allFeatures = mkBoolOpt true "Whether to enable all features. Set to false for safe boot mode with minimal services.";
    ipAddress = mkOpt types.str "" "Main static management IP address with CIDR";
    vlanIpAddress = mkOpt types.str "" "Additional IP with CIDR for tagged VLAN on mgmnt interface";
    vlanId = mkOpt types.int 1 "VLAN ID for the tagged VLAN";
    interfaceMac = mkOpt types.str "" "MAC of the primary fabric (k3s/mgmt) NIC. The ConnectX-7 ports are the dedicated RDMA interconnect — the k3s fabric should be on the standard NIC (like astrolabe). Pin this once hardware arrives.";
    interfaceDriver = mkOpt types.str "" "Driver of the primary fabric NIC (e.g. r8125). Used as a fallback when interfaceMac is unset. NOTE: do not use mlx5_core here — those ports are the ConnectX interconnect, not the k3s fabric.";
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
      inputs.nixos-dgx-spark.packages.${pkgs.stdenv.hostPlatform.system}.perftest
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
        k8s = mkIf cfg.allFeatures {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = false;
          nodeIp = cfg.k8sNodeIp;
          nodeIface = cfg.k8sNodeIface;
          serverAddr = cfg.k8sServerAddr;
          networkType = "standard";
          role = "agent"; # Worker/Agent node
          extraArgs = [
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
      firewall.allowedTCPPorts = [
        5201 # iperf
      ];
      useDHCP = false;
      interfaces = { };
      nameservers = [
        "172.16.1.1"
        "1.1.1.1"
        "9.9.9.9"
      ];
      enableIPv6 = false;
      networkmanager.enable = false;
    };

    # systemd-networkd configuration — same pattern as astrolabe.
    # The primary fabric NIC is the standard 10GbE port (k3s + mgmnt, VLAN 10);
    # the ConnectX-7 25GbE ports are reserved for the RDMA interconnect and are
    # addressed per-boot via nccl-net-setup, not here.
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
        "11-mgmnt" = {
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
        "21-mgmnt-vlan" = mkIf (cfg.vlanIpAddress != "") {
          matchConfig.Name = "mgmnt.${toString cfg.vlanId}";
          networkConfig = {
            DHCP = "no";
            IPv6AcceptRA = "no";
          };
          linkConfig.MTUBytes = "9000";
          address = [ "${cfg.vlanIpAddress}" ];
        };
      };
    };
  };
}
