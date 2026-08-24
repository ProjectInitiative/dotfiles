{
  config,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
{
  # Existing filesystems on the Vestry disk. Keep these UUIDs stable so
  # remote rebuilds do not depend on Disko partition labels.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/36d14db0-3771-42f0-9f8c-a044ea5a1174";
    fsType = "ext4";
    options = [ "x-initrd.mount" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2235-A6D1";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };
  # ── Boot ────────────────────────────────────────────────────────────────
  # 
  boot.kernelParams = [ 
    # Forces the headless generic video driver (simple-framebuffer) to keep 
    # the video output pin permanently active. This prevents the server from 
    # dropping the video signal when the Sipeed NanoKVM Lite is power-cycled 
    # or disconnected remotely.
    "video=Unknown-1:e" 
  ];
  # systemd-boot for a standard EFI mini-pc
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  enableCommonEncryption = mkForce false;
  sops = mkForce {
    defaultSopsFile = ./secrets.enc.yaml;
    age.sshKeyPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
    ];
    secrets = {
      tailscale_auth_key = { };
    };
  };

  # ── SSH (hardened, key-only — keys come from the kylepzak user module) ──
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # ── Networking ──────────────────────────────────────────────────────────
  # DHCP on ethernet via systemd-networkd. For a church LAN this is usually
  # right; switch to a static IP (or NetworkManager) if the LAN requires it.
  networking = {
    useNetworkd = true;
    firewall.enable = true;
  };

  systemd.network.networks."10-ethernet" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
    };
  };

  # ── Host config: everything inline, no host module ──────────────────────
  ${namespace} = {
    user.includePassword = false;

    system = {
      nix-config = enabled;
      locale = enabled;
      # Show IPs on the console — handy for a headless box on DHCP
      console-info.ip-display = enabled;
    };

    networking = {
      tailscale = {
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


    virtualization = {
      docker = enabled;
      podman = enabled;
    };
  };

  # ── Home config: barebones — terminal env only ──────────────────────────
  # The shared kylepzak home (homes/x86_64-linux/kylepzak) pulls in browsers,
  # AI, messengers, backup and digital-creation suites by default. This box is
  # a docker host, so trim it down to just the standard terminal env. Remove
  # this override later if you want the full home config back.
  home-manager.users.kylepzak.${namespace} = {
    users.kylepzak.includeSSH = false;
    cli-apps.atuin.autoLogin = mkForce false;

    browsers = {
      firefox.enable = mkForce false;
      chrome.enable = mkForce false;
      chromium.enable = mkForce false;
      librewolf.enable = mkForce false;
      tor.enable = mkForce false;
    };
    suites = {
      ai.enable = true;
      development.enable = true;
      backup.enable = mkForce false;
      messengers.enable = mkForce false;
      digital-creation.enable = mkForce false;
    };
    tools.ghostty.enable = mkForce false;
  };
}
