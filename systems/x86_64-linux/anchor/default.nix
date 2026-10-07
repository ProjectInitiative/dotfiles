{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
{
  # Existing filesystems on the Anchor disk. Keep these UUIDs stable so
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

  zramSwap = {
    enable = true;
    algorithm = "zstd"; # Best compression ratio for servers
    memoryPercent = 15;
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
    firewall = {
      enable = true;
      allowedTCPPorts = [ 8080 ];
      #     allowedUDPPortRanges = [
      #       { from = 4000; to = 4007; }
      # ];
    };
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

  # ── UPS monitoring (NUT, reporting-only) ────────────────────────────────
  # Cyber Power PR1500LCDRT2U, USB-attached (lsusb: 0764:0601) — the MDF UPS.
  # Driver + upsd only: anchor never shuts anything down (upsmon disabled);
  # upsc now, Grafana scrape later. Self-tests via upscmd will want a upsd
  # user + password later — anchor's own sops file is the place for it.
  # Verify after deploy: upsc church-ups@localhost
  power.ups = {
    enable = true;
    mode = "standalone";
    ups.church-ups = {
      driver = "usbhid-ups";
      port = "auto";
      directives = [ "vendorid = 0764" ];
    };
    upsmon.enable = false;
  };

  environment.systemPackages = with pkgs; [
    nut
  ];

  # Deploy trust: paths pushed from the build hosts must be accepted by the
  # local daemon (common encryption is off here, so the usual grant from the
  # common encrypted module doesn't apply).
  nix.settings = {
    trusted-users = [
      "root"
      "kylepzak"
    ];
    trusted-public-keys = [
      "tugboat:r+QK20NgKO/RisjxQ8rtxctsc5kQfY5DFCgGqvbmNYc="
    ];
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
