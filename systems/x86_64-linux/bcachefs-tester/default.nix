{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
{
  projectinitiative = {
    hosts = {
      base-vm = enabled;
    };
    networking = {
      tailscale = enabled;
    };

    services = {
      health-reporter = {
        enable = true;
        telegramTokenPath = config.sops.secrets.health_reporter_bot_api_token.path;
        telegramChatIdPath = config.sops.secrets.telegram_chat_id.path;
        excludeDrives = [
          "loop"
          "ram"
          "sr"
        ]; # Default exclusions
        reportTime = "08:00"; # Send report at 8 AM
      };
    };
  };
  boot.binfmt = {
    emulatedSystems = [ "aarch64-linux" ];
  };
  # Basic bcachefs support
  boot.supportedFilesystems = [ "bcachefs" ];
  boot.kernelModules = [ "bcachefs" ];

  # Create persistent storage location
  systemd.tmpfiles.rules = [
    "d /var/lib/bcachefs-test 0755 root root -"
  ];

  # Late-mounting service
  systemd.services.mount-bcachefs-test = {
    description = "Mount bcachefs test filesystem";
    path = [
      pkgs.bcachefs-tools
      pkgs.util-linux
    ];

    # Start after basic system services are up
    after = [
      "network.target"
      "local-fs.target"
      "multi-user.target"
    ];

    # Don't consider boot failed if this service fails
    wantedBy = [ "multi-user.target" ];

    # Service configuration
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p /mnt/bcachefs";
    };

    # The actual mount script
    script = ''

      # Create images if they don't exist
      if [ ! -f /var/lib/bcachefs-test/disk1.img ]; then
        dd if=/dev/zero of=/var/lib/bcachefs-test/disk1.img bs=1M count=4096
      fi
      if [ ! -f /var/lib/bcachefs-test/disk2.img ]; then
        dd if=/dev/zero of=/var/lib/bcachefs-test/disk2.img bs=1M count=8196
      fi
      if [ ! -f /var/lib/bcachefs-test/disk3.img ]; then
        dd if=/dev/zero of=/var/lib/bcachefs-test/disk3.img bs=1M count=8196
      fi

      # Clean up any existing loop devices
      losetup -D

      # Set up loop devices
      LOOP1=$(losetup -f --show /var/lib/bcachefs-test/disk1.img)
      LOOP2=$(losetup -f --show /var/lib/bcachefs-test/disk2.img)
      LOOP3=$(losetup -f --show /var/lib/bcachefs-test/disk3.img)

      # Format if not already formatted
      if ! blkid -o value -s TYPE $LOOP1 | grep -q 'bcachefs'; then
        bcachefs format \
          --compression=lz4 \
          --replicas=2 \
          --metadata_replicas_required=1 \
          --data_replicas_required=1 \
          --label=ssd.ssd1 $LOOP1 \
          --label=hdd.hdd1 $LOOP2 \
          --label=hdd.hdd2 $LOOP3 \
          --promote_target=ssd \
          --foreground_target=ssd \
          --background_target=hdd 
      fi

      # Mount the filesystem if not already mounted
      if ! mountpoint -q /mnt/bcachefs; then
        # mount -t bcachefs -o direct,sync $LOOP1 /mnt/bcachefs
        mount -t bcachefs $LOOP1:$LOOP2:$LOOP3 /mnt/bcachefs
      fi
    '';

    # Clean up on service stop
    preStop = ''
      if mountpoint -q /mnt/bcachefs; then
        umount /mnt/bcachefs
      fi
      losetup -D
    '';
  };

  # Required packages
  environment.systemPackages = with pkgs; [
    bcachefs-tools
    util-linux
  ];

}
