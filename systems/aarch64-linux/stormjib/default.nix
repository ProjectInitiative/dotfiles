# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).
#
# nix build .\#nixosConfigurations.stormjib.config.system.build.rockchipImages

{
  config,
  inputs,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  armBoot =
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true" then
      inputs.nixos-on-arm.bootModules
    else
      inputs.nixos-on-arm.bootModulesCross;
in
{
  imports = armBoot.e52c;

  boot.supportedFilesystems.zfs = lib.mkForce false;
  hardware.deviceTree.kernelPackage = lib.mkForce config.boot.kernelPackages.kernel;

  # Use out-of-tree r8125 driver — in-tree r8169 has 2.5G link flapping issue.
  # r8125 v9.016.01 from Debian, built against the patched kernel.
  boot.blacklistedKernelModules = [ "r8169" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];
  boot.kernelModules = [ "r8125" ];
  hardware.firmware = [ pkgs.linux-firmware ];

  rockchip.image.bootPartitionSize = "1G";

  boot.kernelParams = [
    "pcie_aspm=off"
  ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", NAME=="enP*", RUN+="${pkgs.ethtool}/bin/ethtool --set-eee $name eee off"
  '';

  # Keep as reference — may not be needed if firmware resolves the issue
  # systemd.services.fix-r8169-link = {
  #   ...
  # };

  # Try without PCIe overlay - default link training may work better
  hardware.deviceTree.enable = true;
  hardware.deviceTree.overlays = [
  ];

  # Limit boot entries to prevent ESP overflow (253M partition)
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 4;
    efi.canTouchEfiVariables = true;
  };

  projectinitiative = {
    services = {
      monitoring = {
        enable = true;
        openFirewall = true;

        prometheus = {
          enable = true;
          retentionTime = "90d";

          scrapeConfigs = {
            nodes = {
              targets = [
                "172.16.1.51:9100"
                "172.16.1.52:9100"
                "172.16.1.53:9100"
                "lighthouse-east:9100"
                "lighthouse-west:9100"
              ];
            };
            smart-devices = {
              targets = [
                "172.16.1.51:9633"
                "172.16.1.52:9633"
                "172.16.1.53:9633"
                "lighthouse-east:9633"
                "lighthouse-west:9633"
              ];
            };
          };
        };

        grafana.enable = false;

        exporters = {
          node.enable = true;
          smartctl.enable = true;
        };
      };
    };
    hosts.masthead = {
      stormjib.enable = true;
      interfaces = {
        wan = "enP3p49s0";
        lan = "enP4p65s0";
        sync = "enP5p81s0";
      };
      wanSpoofMac = "00:48:54:20:12:0e";
    };
    networking = {
      tailscale = {
        enable = true;
        ephemeral = false;
        extraArgs = [
          "--accept-routes"
        ];
      };
    };
    system = {
      console-info.ip-display.enable = true;
    };
  };

  console.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # ── Docker + omada-controller (carried over from the OpenWrt router) ──
  projectinitiative.virtualization.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers.omada-controller = {
      image = "mbentley/omada-controller:latest";
      autoStart = true;
      environment.TZ = "America/Chicago";
      volumes = [
        "/var/lib/omada-controller/data:/opt/tplink/EAPController/data"
        "/var/lib/omada-controller/logs:/opt/tplink/EAPController/logs"
      ];
      ports = [
        "8043:8043/tcp" # mgmt HTTPS
        "8088:8088/tcp" # mgmt HTTP
        "8843:8843/tcp" # portal HTTPS
        "27001:27001/udp" # discovery
        "29810:29810/udp" # device adoption
        "29811-29816:29811-29816/tcp" # device inform/upgrade
      ];
    };
  };

  # Omada ports reachable from internal networks only (mirrors OpenWrt's
  # Allow-omada-controller src=lan rule) — scoped to LAN + VLAN subinterfaces
  # so nothing is exposed on the WAN NIC.
  networking.firewall.interfaces =
    let
      internalIfaces = [
        "enP4p65s0"
        "enP4p65s0.18"
        "enP4p65s0.20"
        "enP4p65s0.21"
      ];
    in
    builtins.listToAttrs (
      map (iface: {
        name = iface;
        value = {
          allowedTCPPorts = [
            8043
            8088
            8843
            29811
            29812
            29813
            29814
            29815
            29816
          ];
          allowedUDPPorts = [
            27001
            29810
          ];
        };
      }) internalIfaces
    );

  environment.systemPackages = with pkgs; [
    ethtool
    pciutils
    iperf3
  ];

}
