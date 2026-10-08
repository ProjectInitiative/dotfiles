# Watchman estate — the church-site NanoPi NEO3 Plus SBCs (capstan pattern).
#
# watchman-idf (IDF room) and watchman-mdf (MDF room) both enable this
# module and share ONE sops secret file (secrets.enc.yaml here) — the same
# way capstan1/2/3 share capstan/secrets.enc.yaml. Everything common to the
# estate lives here: the stripped terminal-only home, hardened SSH,
# tailscale, and NUT against whichever UPS is USB-attached to the box.
# Per-host bits (hostname, toggles, future services like the Unifi alarm
# bridge on watchman-mdf) live in the systems/<arch>/<host>/default.nix
# files.
#
# NUT posture: REPORTING ONLY — the driver + upsd run so `upsc` (and the
# eventual Grafana scrape) can read UPS state, but upsmon is DISABLED:
# these boxes never shut anything down. Self-tests via upscmd will want a
# upsd user + password — add those to the shared sops file when needed.
#
# Initial flash image (either host):
#   nix build .#nixosConfigurations.<host>.config.system.build.rockchipImages
# Serial console: UART0_M0 @ 0xff9f0000, 1500000 8n1 (3-pin header) —
# documented in boot/nanopi-neo3-plus-boot.nix in nixos-on-arm.
{
  config,
  inputs,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.watchman;

  armBoot =
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true" then
      inputs.nixos-on-arm.bootModules
    else
      inputs.nixos-on-arm.bootModulesCross;
in
{
  options.${namespace}.hosts.watchman = {
    enable = mkBoolOpt false "Whether to enable the watchman church-site estate (NanoPi NEO3 Plus SBCs).";
    nut = {
      enable = mkBoolOpt true "Run NUT against the locally USB-attached UPS (reporting only — no shutdown duty).";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      boot.supportedFilesystems.zfs = mkForce false;
      hardware.deviceTree.kernelPackage = mkForce config.boot.kernelPackages.kernel;

      # Shared estate sops store (capstan pattern): one secrets.enc.yaml
      # encrypted to every watchman host key + the master key. The common
      # encrypted module stays off — includeSSH/includePassword below keep
      # kylepzak_ssh_key and user_password from ever being referenced, so
      # tailscale_auth_key is the only secret this estate needs.
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

      # Key-only boxes: no hashed password file; sudo is NOPASSWD via the
      # user module.
      ${namespace} = {
        user.includePassword = false;

        # Tailscale — remote management path for the church site; auth key
        # comes from sops (tailscale_auth_key — the module reads it
        # automatically when ephemeral = false). Plain tailnet member: no
        # subnet routes advertised, no routes accepted.
        networking.tailscale = {
          enable = true;
          ephemeral = false;
          extraArgs = [
            "--accept-routes=false"
            "--advertise-routes="
            "--snat-subnet-routes=true"
          ];
        };

        # Eternal Terminal — resilient remote shell for the IDF/MDF rooms
        # (survives NAT/connection changes where plain SSH drops). Server on
        # the default port 2022, firewall opened by the service module.
        services.eternal-terminal = enabled;
      };

      networking = {
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

      # usbutils for `lsusb` (the UPSes read 0764:0601).
      environment.systemPackages = with pkgs; [
        usbutils
      ];

      # Deploy trust: paths pushed from the build hosts (nix-copy-closure /
      # deploy-rs) must be accepted by the local daemon. Same grant the
      # common encrypted module gives hosts with common encryption on —
      # these boxes keep common encryption off, so the grant lives here.
      nix.settings = {
        trusted-users = [
          "root"
          "kylepzak"
        ];
        trusted-public-keys = [
          "tugboat:r+QK20NgKO/RisjxQ8rtxctsc5kQfY5DFCgGqvbmNYc="
        ];
      };

      console.enable = true;

      # ── Home config: barebones — terminal env only ────────────────────────
      # Lighthouse-style force-overrides (mkForce) beat the shared kylepzak
      # home's defaults regardless of merge order; terminal-env stays because
      # the shared home enables it and nothing here touches it.
      # includeSSH=false: the estate sops store only carries
      # tailscale_auth_key. Add kylepzak_ssh_key to the shared sops file and
      # flip this if you ever want SSH keys provisioned on these boxes.
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
    (mkIf cfg.nut.enable {
      # ── UPS monitoring (NUT, reporting-only) ────────────────────────────
      # Cyber Power PR1500LCDRT2U, USB-attached (lsusb: 0764:0601).
      # usbhid-ups speaks CPS HID via its built-in cps-hid subdriver; the
      # vendorid pin makes sure nothing else on the bus can claim the match.
      # Standalone mode runs driver + upsd (localhost only) — but upsmon is
      # DISABLED: these boxes never shut anything down, they only report
      # (upsc now; Grafana scrape later). Self-tests via upscmd will want a
      # upsd user + password — add to the shared sops file when needed.
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

      # nut gives upsc/upscmd for verification.
      environment.systemPackages = with pkgs; [
        nut
      ];
    })
  ]);
}
