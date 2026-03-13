{
  config,
  pkgs,
  inputs,
  namespace,
  modulesPath,
  lib,
  ...
}:
{

  imports = inputs.nixos-on-arm.bootModules.orangepi5ultra;

  
  # hardware.deviceTree.overlays = [
  #   {
  #     name = "rk3588-npu";
  #     dtsFile = "${inputs.self}/modules/nixos/hosts/lightship/rk3588-npu.dts";
  #   }
  # ];

  home-manager.backupFileExtension = "backup";

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.supportedFilesystems.zfs = lib.mkForce false;
  boot.supportedFilesystems.nfs = true;

  hardware.deviceTree.kernelPackage = lib.mkForce config.boot.kernelPackages.kernel;

  environment.systemPackages = with pkgs; [
    pkgs.${namespace}.rknpu2
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
        runtimeInputs = [ pkgs.iputils pkgs.systemd ];
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
      remotes = [{
        name = "origin";
        url = "https://github.com/projectinitiative/dotfiles.git";
        branches.main.name = "main";
      }];
      livelinessCheckCommand = "${livelinessCheck}/bin/comin-liveliness-check";
    };

  networking = {
    firewall = {
      # allowedTCPPorts = [ 5353 ];
      allowedUDPPorts = [ 5353 ];
    };
    networkmanager = {
      enable = false;
      # unmanaged = [
      #   "enP3p49s0"  # Don't let NetworkManager manage the physical interface
      # ];
    };
    useDHCP = false;
    
    # VLAN configuration for vlan21
    interfaces.enP3p49s0.useDHCP = false;
    vlans."vlan21" = {
      id = 21;
      interface = "enP3p49s0";
    };
    interfaces.vlan21.useDHCP = true;
  };

  # NFS mount for frigate camera feed storage offloaded to dinghy's bcachefs pool
  fileSystems."/mnt/dinghy/frigate" = {
    device = "100.119.112.42:/frigate";
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
    };

    services = {
        # monitoring.alloy.enable = lib.mkForce false;
    };

  };

}
