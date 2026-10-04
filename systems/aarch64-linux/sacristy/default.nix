# Sacristy — NanoPi NEO3 Plus (RK3528A) on-site at the church.
#
# Sibling of vestry (also church-site): headless, minimal, dedicated to
# monitoring the site's UPS. Boots via the nixos-on-arm board modules
# (U-Boot + patched RK3528 kernel), deployed like the other SBCs.
#
# Initial flash image:
#   nix build .#nixosConfigurations.sacristy.config.system.build.rockchipImages
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

  # No host sops key enrolled yet. Once the board is on-site and its host SSH
  # key exists, follow the vestry pattern (own secrets.enc.yaml +
  # age.sshKeyPaths, sops-hostkey-tool for enrollment) and drop this override.
  enableCommonEncryption = lib.mkForce false;

  # No sops secret store for this host yet → skip the hashed password file
  # too (vestry pattern). Login stays key-only SSH; sudo is NOPASSWD via the
  # user module. Revisit when secrets are enrolled.
  ${namespace}.user.includePassword = false;

  networking = {
    hostName = "sacristy";
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
  # TODO: enable once the UPS model and connection are known:
  #   - USB-attached to this box → mode "standalone" + usbhid-ups (APC/Eaton/
  #     MGE) or nutdrv_qx (many budget models); identify with lsusb, driver
  #     list in ${nut}/share/driver.list.
  #   - Monitored by another host → mode "netclient" and point
  #     power.ups.upsmon.monitor at church-ups@<nut-server>.
  # Shape (from nixos/modules/services/monitoring/ups.nix):
  #   power.ups = {
  #     enable = true;
  #     mode = "standalone";
  #     ups.church-ups = {
  #       driver = "usbhid-ups";
  #       port = "auto";
  #     };
  #     upsmon.monitor.church-ups = {
  #       user = "upsmon";
  #       # passwordFile must exist; generate with sops when secrets land
  #       passwordFile = "/run/secrets/upsmon-password";
  #     };
  #   };
  #   power.ups.users.upsmon.passwordFile = "/run/secrets/upsmon-password";
  # If this host only *reports* (no shutdown duty), set monitor type "slave"
  # or rely on Prometheus node_exporter + upsc instead.

  # nut provides upsc/upscmd for ad-hoc checks; usbutils for `lsusb` to
  # identify the UPS.
  environment.systemPackages = with pkgs; [
    nut
    usbutils
  ];

  console.enable = true;

  # ── Home config: barebones — terminal env only ────────────────────────────
  # Same trim as vestry: the shared kylepzak home pulls in browsers, AI,
  # messengers, backup and digital-creation suites by default. This box is a
  # single-purpose UPS monitor, so keep just the standard terminal env.
  # includeSSH=false because there is no sops secret store for this host yet;
  # once secrets are enrolled (host key in .sops.yaml, re-encrypt), consider
  # following the stormjib path (common encryption) or vestry (own
  # secrets.enc.yaml) and re-enabling SSH key provisioning.
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
