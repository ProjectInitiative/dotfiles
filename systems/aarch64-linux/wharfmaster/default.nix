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
  armBoot =
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true" then
      inputs.nixos-on-arm.bootModules
    else
      inputs.nixos-on-arm.bootModulesCross;
in
{

  imports = armBoot.orangepi5ultra;

  # hardware.deviceTree.overlays = [
  #   {
  #     name = "rk3588-npu";
  #     dtsFile = "${inputs.self}/modules/nixos/hosts/lightship/rk3588-npu.dts";
  #   }
  # ];

  home-manager.backupFileExtension = "backup";

  boot.supportedFilesystems.zfs = lib.mkForce false;
  boot.supportedFilesystems.nfs = true;

  boot.initrd.availableKernelModules =
    with lib;
    mkForce [
      "dw_mmc_rockchip"
      "nvme"
      "pcie_rockchip_host"
    ];

  hardware.deviceTree.kernelPackage = lib.mkForce config.boot.kernelPackages.kernel;

  environment.systemPackages = with pkgs; [
    pkgs.${namespace}.rknpu2
    pkgs.${namespace}.mpp-rockchip
  ];

  programs.zsh.enable = true;

  # Enable and configure SSH, restricting access to public keys only
  services.openssh = {
    enable = true;
    # Disable password-based authentication for security.
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false; # Disables keyboard-interactive auth, often a fallback for passwords.
      PermitRootLogin = "prohibit-password"; # Allows root login with a key, but not a password.
    };
  };

  services.comin =
    let
      livelinessCheck = pkgs.writeShellApplication {
        name = "comin-liveliness-check";
        runtimeInputs = [
          pkgs.iputils
          pkgs.systemd
        ];
        text = ''
          echo "--- Starting Health Checks ---"

          echo "Pinging gateway 192.168.21.1..."
          ping -c 5 192.168.21.1

          echo "Checking docker service status..."
          systemctl is-active --quiet docker

          echo "--- Health Checks Complete ---"
        '';
      };
    in
    {
      enable = false;
      remotes = [
        {
          name = "origin";
          url = "https://github.com/projectinitiative/dotfiles.git";
          branches.main.name = "main";
        }
      ];
      livelinessCheckCommand = "${livelinessCheck}/bin/comin-liveliness-check";
    };

  networking = {
    # Static global DNS in resolved.conf — belt-and-suspenders fallback.
    # Primary DNS comes from networkd lease push (UseDNS=true) and the shared
    # tailscale module's split-DNS (tailscale0 -> Quad100).
    # History: this host ran scripted+dhcpcd, whose lease-DNS path
    # (resolvconf) is force-disabled by services.resolved.enable in nixpkgs
    # (resolved.nix sets networking.resolvconf.enable = false), so the
    # DHCP-provided 192.168.21.1 was silently discarded and general lookups
    # SERVFAILed (fixed 2026-10-08, OQ-0026).
    nameservers = [
      "192.168.21.1" # router/lease resolver — local (.lan) names
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall = {
      # allowedTCPPorts = [ 5353 ];
      allowedUDPPorts = [ 5353 ];
    };

    # systemd-networkd — the estate standard (astrolabe, anchor, dinghy).
    # Migrated from scripted+dhcpcd 2026-10-08 (OQ-0026): networkd pushes
    # lease DNS to resolved natively over D-Bus. (A 2025-11-10 attempt,
    # 388835a, was rolled back same day — this redo ships with the rollback
    # watchdog below because the box is headless: no console to pick a boot
    # entry if it breaks.)
    useNetworkd = true;
    useDHCP = false;

    # VLAN 21 = IoT LAN. With useNetworkd, nixpkgs generates the 40-vlan21
    # netdev and the 40-enP3p49s0.network (VLAN= attachment) from this.
    vlans."vlan21" = {
      id = 21;
      interface = "enP3p49s0";
    };
    interfaces.vlan21.useDHCP = true;
  };

  # Docker bridges/veths + tailscale0 are unmanaged — don't let them stall
  # network-online.target; any managed interface reaching routable suffices.
  systemd.network.wait-online.anyInterface = true;

  # NFS mount for frigate camera feed storage offloaded to dinghy's bcachefs pool
  fileSystems."/mnt/dinghy/frigate" = {
    device = "dinghy.taildeab2.ts.net:/frigate";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600" # Disconnect after 10 mins of inactivity
      "x-systemd.mount-timeout=30"
      "nfsvers=4.2"
      "soft" # Use soft mount to prevent system freeze if dinghy is down
      "_netdev" # Ensure systemd knows this is a network mount
    ];
  };

  # setup funnel for home-assistant
  systemd.services.tailscale-funnel = {
    description = "Tailscale Funnel";
    after = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg 8123";
      User = "root"; # Funnel needs root to bind to privileged ports
    };
  };

  home-manager = {

    users.kylepzak.${namespace} = {
      suites = {
        development.enable = true;
      };
    };

  };

  projectinitiative = {

    networking = {
      tailscale = {
        enable = true;
        ephemeral = false;
        extraArgs = [
          "--accept-routes=true"
          # "--advertise-routes=10.0.0.0/24"
          # "--snat-subnet-routes=false"
          "--accept-dns=true"
          # "--accept-routes=false"
          "--advertise-routes="
          "--snat-subnet-routes=true"
        ];
      };
    };
    suites = {
      development = {
        enable = true;
      };
      monitoring = {
        enable = true;
        extraAlloyJournalRelabelRules = [
          {
            source_labels = [ "__journal__systemd_unit" ];
            regex = "docker.service";
            action = "drop";
          }
        ];
      };
      loft = {
        enableClient = true;
      };
    };

    system = {
      nix-config.enable = true;
      logging = {
        enable = true;
        ramLogging = true;
      };
    };

    services = {
      # monitoring.alloy.enable = lib.mkForce false;
    };

  };

}
