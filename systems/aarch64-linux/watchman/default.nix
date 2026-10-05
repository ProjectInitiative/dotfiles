# Watchman — NanoPi NEO3 Plus (RK3528A) on-site at the church.
#
# Sibling of anchor (also church-site): headless, minimal, dedicated to
# monitoring the site's UPS. Boots via the nixos-on-arm board modules
# (U-Boot + patched RK3528 kernel), deployed like the other SBCs.
#
# Initial flash image:
#   nix build .#nixosConfigurations.watchman.config.system.build.rockchipImages
# Serial console: UART0_M0 @ 0xff9f0000, 1500000 8n1 (3-pin header) —
# documented in boot/nanopi-neo3-plus-boot.nix in nixos-on-arm.
{
  config,
  inputs,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  armBoot =
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true" then
      inputs.nixos-on-arm.bootModules
    else
      inputs.nixos-on-arm.bootModulesCross;
in
{
  imports = armBoot.nanopineo3plus;

  boot.supportedFilesystems.zfs = lib.mkForce false;
  hardware.deviceTree.kernelPackage = lib.mkForce config.boot.kernelPackages.kernel;

  rockchip.image.buildVariants = {
    full = true;
    sdcard = true;
    ubootOnly = true;
  };

  # Own sops store (anchor pattern): per-host secrets.enc.yaml encrypted to
  # the host SSH key + kylepzak/thinkpad. The common encrypted module stays
  # off — includeSSH/includePassword below keep kylepzak_ssh_key and
  # user_password from ever being referenced, so tailscale_auth_key and
  # upsmon_password are the only secrets this host needs.
  enableCommonEncryption = mkForce false;
  sops = mkForce {
    defaultSopsFile = ./secrets.enc.yaml;
    age.sshKeyPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
    ];
    secrets = {
      tailscale_auth_key = { };
      # Local upsd/upsmon auth password (arbitrary random string, only ever
      # compared between two local services). Generate with:
      #   openssl rand -base64 18
      upsmon_password = { };
    };
  };

  # Key-only box (anchor keeps this false too): no hashed password file,
  # sudo is NOPASSWD via the user module.
  ${namespace} = {
    user.includePassword = false;

    # Tailscale — remote management path for the church site; auth key comes
    # from sops (tailscale_auth_key — the module reads it automatically when
    # ephemeral = false). Anchor posture: plain tailnet member — no subnet
    # routes advertised, no routes accepted.
    networking.tailscale = {
      enable = true;
      ephemeral = false;
      extraArgs = [
        "--accept-routes=false"
        "--advertise-routes="
        "--snat-subnet-routes=true"
      ];
    };
  };

  networking = {
    hostName = "watchman";
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
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

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 15;
  };

  # ── UPS monitoring (NUT) ─────────────────────────────────────────────────
  # Cyber Power PR1500LCDRT2U, USB-attached to this box (lsusb: 0764:0601).
  # usbhid-ups speaks CPS HID via its built-in cps-hid subdriver (the NUT
  # DDL lists the near-identical PR1500RT2U on usbhid-ups); the vendorid
  # pin makes sure nothing else on the bus can claim the match.
  # Standalone mode = driver + upsd (localhost only) + upsmon with local
  # shutdown duty (MINSUPPLIES 1, default SHUTDOWNCMD). If another church
  # host ever needs to watch this UPS, switch mode to "netserver", add an
  # upsd LISTEN entry for that interface, and set openFirewall.
  # Verify after deploy: upsc church-ups@localhost
  power.ups = {
    enable = true;
    mode = "standalone";
    ups.church-ups = {
      driver = "usbhid-ups";
      port = "auto";
      directives = [ "vendorid = 0764" ];
    };
    users.upsmon = {
      passwordFile = config.sops.secrets.upsmon_password.path;
      upsmon = "primary";
    };
    upsmon.monitor.church-ups = {
      user = "upsmon"; # passwordFile defaults to users.upsmon.passwordFile
    };
  };

  # nut gives upsc/upscmd for verification; usbutils for `lsusb`.
  environment.systemPackages = with pkgs; [
    nut
    usbutils
  ];

  console.enable = true;

  # ── Home config: barebones — terminal env only ────────────────────────────
  # Single-purpose UPS monitor: no dev tools, no AI, no interactive
  # Bitwarden tooling. Lighthouse-style force-overrides (mkForce) beat the
  # shared kylepzak home's defaults regardless of merge order; terminal-env
  # stays because the shared home enables it and nothing here touches it.
  # includeSSH=false: this host's sops store only carries tailscale_auth_key.
  # Add kylepzak_ssh_key to watchman/secrets.enc.yaml and flip this if you
  # ever want the SSH key provisioned here.
  home-manager.users.kylepzak.${namespace} = {
    users.kylepzak.includeSSH = false;
    cli-apps.atuin.autoLogin = mkForce false;
    security.bitwarden.enable = mkForce false;

    browsers = {
      firefox.enable = mkForce false;
      chrome.enable = mkForce false;
      chromium.enable = mkForce false;
      librewolf.enable = mkForce false;
      tor.enable = mkForce false;
    };
    suites = {
      ai.enable = mkForce false;
      development.enable = mkForce false;
      backup.enable = mkForce false;
      messengers.enable = mkForce false;
      digital-creation.enable = mkForce false;
    };
    tools.ghostty.enable = mkForce false;
  };
}
