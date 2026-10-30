{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  inputs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.argo;
in
{
  options.${namespace}.hosts.argo = with types; {
    enable = mkBoolOpt false "Whether or not to enable the argo VM configuration.";
    # false (default): legacy image-bootstrap mode — /nix stays the image's
    #   root-fs store and argo-nix-store-rotate seeds /data/nix + bind-flips
    #   it over /nix at stage-2. Used by the baked qcow2, because the fstab
    #   bind would be mounted by the INITRD before any seeding could run,
    #   and an empty /data/nix under a fresh data disk means no init.
    # true (live VM): /nix is a REAL initrd-mounted bind of /data/nix.
    #   The initrd already mounts /data (neededForBoot); ordering the bind
    #   after it means stage-1 sops-install-secrets sees the same store
    #   rebuilds write into — fixing the 2026-10-30 failure where the
    #   stage-2-only flip left the initrd on the frozen image store.
    #   Requires /data/nix to already contain the booting closure (it does:
    #   the rotate unit has kept it seeded since the image). Recovery if
    #   /data is ever wiped: grub-rollback to a pre-bind generation.
    nixFromDataDisk = mkBoolOpt false "Mount /nix as an initrd bind of /data/nix (ordered after /data).";
  };

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  config = mkIf cfg.enable {

    # Bootloader & fileSystems handled by NixOS kubevirt module (GRUB on /dev/vda)
    # services.qemuGuest, services.openssh, services.cloud-init also from kubevirt

    # ── Sops ─────────────────────────────────────────────────────────────────
    # The image's baked /etc/ssh/ssh_host_ed25519_key is enrolled as an age
    # recipient (&ssh_argo) in .sops.yaml, so sops-nix renders secrets at boot
    # normally (including /run/secrets/sensitive_not_secret_age_key, which the
    # home-manager activation build env requires). Do NOT re-add the old
    # "sops bypass for image builds" (mkForce-empty keys) — that was what left
    # /run/secrets missing and bricked home-manager activation (OQ-0041).
    # Caveat: an image rebuild bakes a NEW host key → re-enroll via
    # sops-hostkey-tool fetch-remote + .sops.yaml + sops updatekeys.

    # ── Services that the kubevirt image format normally provides ──────────
    # The live nixosConfigurations.argo build does NOT include the
    # nixos-generators format module, which is what enables qemu-guest-agent,
    # sshd and cloud-init for the image. Without these the live system boots
    # with no remote access at all (learned 2026-10-22: a switch to this
    # closure stopped sshd + qemu-ga and bricked remote access).
    services.qemuGuest.enable = true;
    services.openssh.enable = true;
    # The image got its network config from cloud-init's fallback DHCP; the
    # live closure has no cloud-init, so DHCP must be explicit or enp1s0
    # never gets an address.
    networking.useDHCP = true;

    # ── SSH config (service enabled by kubevirt module) ─────────────────────
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };

    # ── Users ───────────────────────────────────────────────────────────────
    # Standard estate user module (kylepzak, keys from ssh-pub-keys input,
    # NOPASSWD sudo via wheelNeedsPassword=false). includePassword=false
    # because this VM has no sops age key (bootstrap via cloud-init).
    users.users.kylepzak.extraGroups = [
      "wheel"
      "docker"
    ];

    # ── Development Environment ─────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      cloud-utils
      git
      vim
      htop
      jq
      curl
      wget
    ];

    ${namespace} = {
      user = {
        enable = true;
        includePassword = false;
      };
      settings.stateVersion = "26.05";

      system = {
        console-info.ip-display = enabled;
        nix-config = enabled;
        locale = enabled;
      };

      virtualization = {
        podman = enabled;
        docker = enabled;
      };

      services.eternal-terminal = enabled;
      suites.loft.enableClient = true;
    };

    # ── Home Manager ────────────────────────────────────────────────────────
    home-manager = {
      backupFileExtension = "backup";
      useGlobalPkgs = true;
      users.kylepzak = {
        home.stateVersion = "26.05";
        ${namespace}.suites.development.enable = true;
      };
    };

    # ── Nix ─────────────────────────────────────────────────────────────────
    # ── Storage ────────────────────────────────────────────────────────────
    # kubevirt virtio disks: vda = 32Gi root (disposable), vdb = 1Ti data
    # (JuiceFS blank DV, serial "argodata" -> stable by-id path).
    # /data holds everything precious (and, in live mode, the nix store).
    #
    # Legacy mode (nixFromDataDisk = false, baked image): the nix store is
    # MIRRORED to /data/nix and bind-mounted over /nix at stage-2
    # (argo-nix-store-rotate below) so heavy builds never touch the root
    # fs and survive root re-imports. Deliberately NOT a fileSystems
    # entry: /nix is hardcoded into NixOS pathsNeededForBoot, so a
    # fileSystems bind gets mounted by the INITRD (sysroot-nix.mount)
    # before any seeding can run, hiding the image's store and freezing
    # the boot ("Failed to isolate default target: Unit data.mount not
    # found"). A stage-2 oneshot can flip the bind safely at any point:
    # until then /nix shows the image store, and the seeded copy is
    # byte-identical, so units execing across the flip get the same
    # binaries either way.
    fileSystems = mkMerge [
      {
        "/data" = {
          device = "/dev/disk/by-id/virtio-argodata";
          fsType = "ext4";
          autoFormat = true;
          autoResize = true;
          neededForBoot = true;
          options = [ "nofail" ];
        };
      }
      (mkIf cfg.nixFromDataDisk {
        # Live VM: initrd-mounted bind. systemd orders a bind after its
        # source path's mount (and we require it explicitly), so /data is
        # up BEFORE /nix flips — the initrd's sops-install-secrets then
        # reads the LIVE store and finds the booting closure's secrets
        # file (fixes the 2026-10-30 "manifest is not valid: failed
        # reading ...-secrets.enc.yaml" -> /run/secrets missing ->
        # home-manager activation failure). nofail degrades to the image
        # store (old behavior) instead of freezing if /data is missing.
        # This is safe to boot ONLY while /data/nix holds the booting
        # closure — true since the rotate unit has kept it seeded; on a
        # wiped /data, grub-rollback to a pre-bind generation to recover.
        "/nix" = {
          device = "/data/nix";
          fsType = "none";
          neededForBoot = true;
          options = [ "bind" "nofail" "noatime" "x-systemd.requires-mounts-for=/data" ];
        };
      })
    ];
    # Legacy image-bootstrap store handling (nixFromDataDisk = false only):
    # seed /data/nix with the booting nix store, then bind it over /nix.
    # The live VM instead binds /nix from /data/nix in the INITRD (see
    # above), where this unit is disabled — no flip needed, and the
    # nix-daemon.socket rebind hack below is unnecessary there.
    # Self-healing: if the data disk's store lacks the booting system
    # closure (fresh disk, wiped data, or a re-imported image with a new
    # closure), the stale copy is wiped and re-seeded from the image.
    # Runs late (after multi-user) and self-guards on the /data mount —
    # the flip is safe at any point because the seeded copy is identical
    # to the image store, so units execing across it get the same bytes.
    systemd.services.argo-nix-store-rotate = mkIf (!cfg.nixFromDataDisk) {
      description = "Seed /data/nix with the booting nix store and bind over /nix";
      after = [ "local-fs.target" "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = ''
        SW=/run/current-system/sw/bin
        RW=/run/wrappers/bin
        n=0
        while ! $SW/mountpoint -q /data; do
          n=$((n+1)); [ $n -gt 120 ] && echo "argo-nix-store-rotate: /data never mounted, skipping" && exit 0
          sleep 1
        done
        $SW/mkdir -p /data/nix
        # /proc/cmdline starts with BOOT_IMAGE=..., so don't anchor ^init=.
        # Fail hard if unparsable — binding an empty dir over /nix bricks the
        # guest, so no-seed-info means no-bind.
        sys=$($SW/sed -n 's/.*[ ]init=\(\/nix\/store\/[^ ]*\).*/\1/p' /proc/cmdline)
        if [ -z "$sys" ]; then
          echo "argo-nix-store-rotate: could not parse init= from cmdline, NOT binding /nix"
          exit 1
        fi
        rel=''${sys#/nix}
        if [ ! -e "/data/nix$rel" ]; then
          echo "argo-nix-store-rotate: seeding nix store to /data/nix (one-time, may take several minutes)"
          $SW/rm -rf /data/nix/*
          if ! $SW/cp -a /nix/. /data/nix/; then
            echo "argo-nix-store-rotate: SEED FAILED, not binding /nix (guest keeps image store)"
            exit 1
          fi
        fi
        $SW/mountpoint -q /nix || $RW/mount --bind /data/nix /nix
        # The bind HIDES the inode nix-daemon.socket is listening on: the
        # socket unit starts at sockets.target (before this unit), binds to
        # the image's /nix, and after the flip the path points at the stale
        # seeded socket file -> ECONNREFUSED for every nix client (incl.
        # nixos-rebuild --target-host and nix copy --to). Re-bind the socket
        # to the new /nix. The service must be stopped first or the socket
        # unit refuses to restart ("socket service already active").
        if $SW/systemctl is-active --quiet nix-daemon.socket; then
          $SW/systemctl stop nix-daemon.service 2>/dev/null || true
          $SW/systemctl restart nix-daemon.socket 2>/dev/null || true
          echo "argo-nix-store-rotate: nix-daemon.socket re-bound to the data-disk /nix"
        fi
        echo "argo-nix-store-rotate: /nix now served from the data disk ($($SW/ls /data/nix/store | $SW/wc -l) store paths)"
      '';
    };

    # Same pattern as /nix: seed /data/home from the image's /home once,
    # then bind /data/home over /home so ~ survives root re-imports.
    # Runs BEFORE multi-user (unlike the /nix flip) so home-manager and
    # anything else reading ~ at target-start sees the data-disk home and
    # never the (stale) image home. /data is x-initrd.mount'ed, so it is
    # present this early; the seed is a no-op once the marker exists and
    # the bind is idempotent every boot.
    systemd.services.argo-home-disk = {
      description = "Seed /data/home with the booting /home and bind over /home";
      after = [ "local-fs.target" ];
      before = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = ''
        SW=/run/current-system/sw/bin
        RW=/run/wrappers/bin
        n=0
        while ! $SW/mountpoint -q /data; do
          n=$((n+1)); [ $n -gt 120 ] && echo "argo-home-disk: /data never mounted, skipping" && exit 0
          sleep 1
        done
        $SW/mkdir -p /data/home
        # Seed once: copy the image home before anything binds over it.
        if [ ! -e /data/home/.home-seeded ]; then
          echo "argo-home-disk: seeding /home to /data/home (one-time)"
          if $SW/cp -a /home/. /data/home/; then
            $SW/touch /data/home/.home-seeded
          else
            echo "argo-home-disk: SEED FAILED, not binding /home (guest keeps image home)"
            exit 1
          fi
        fi
        $SW/mountpoint -q /home || $RW/mount --bind /data/home /home
        echo "argo-home-disk: /home now served from the data disk"
      '';
    };

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    nix.settings.trusted-users = [ "kylepzak" ];
  };
}
