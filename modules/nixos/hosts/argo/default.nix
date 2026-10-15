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
  };

  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  config = mkIf cfg.enable {

    # Bootloader & fileSystems handled by NixOS kubevirt module (GRUB on /dev/vda)
    # services.qemuGuest, services.openssh, services.cloud-init also from kubevirt

    # ── Sops: bypass for image builds (runtime auth via OpenBao/Vault) ──────
    sops.validateSopsFiles = lib.mkForce false;
    sops.age.sshKeyPaths = lib.mkForce [ ];
    sops.age.keyFile = lib.mkForce "/dev/null";
    sops.defaultSopsFile = lib.mkForce (builtins.toFile "empty-sops.yaml" "{}");

    # ── SSH config (service enabled by kubevirt module) ─────────────────────
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };

    # ── Users ───────────────────────────────────────────────────────────────
    users.users.kylepzak = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
      ];
      openssh.authorizedKeys.keyFiles = [ inputs.ssh-pub-keys ];
      initialPassword = "changeme";
    };
    users.users.root.openssh.authorizedKeys.keyFiles = [ inputs.ssh-pub-keys ];

    security.sudo.extraRules = [
      {
        users = [ "kylepzak" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
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
      user.enable = false;
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
    # /data holds everything precious; /nix is a bind so heavy builds never
    # touch the root fs and survive root rebuilds/re-imports.
    fileSystems = {
      "/data" = {
        device = "/dev/disk/by-id/virtio-argodata";
        fsType = "ext4";
        autoFormat = true;
        autoResize = true;
        neededForBoot = false;
      };
      "/nix" = {
        device = "/data/nix";
        fsType = "none";
        options = [ "bind" "x-systemd.requires=data.mount" ];
        depends = [ "/data" ];
      };
    };
    # create /data/nix before the bind mount on a freshly formatted disk
    systemd.services.argo-data-prepare = {
      description = "Prepare argo data disk layout";
      requiredBy = [ "nix.mount" ];
      after = [ "data.mount" ];
      before = [ "nix.mount" ];
      unitConfig.ConditionPathIsMountPoint = "/data";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /data/nix
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
