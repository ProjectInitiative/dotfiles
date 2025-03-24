# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{ pkgs, config, namespace, ... }:
let
  # Create files in the nix store
  hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.stormjib_private_ssh_key;
  hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.stormjib_public_ssh_key;
in
{
  config = {

    environment.etc = {
      "ssh/ssh_host_ed25519_key" = {
        source = hostSSHFile;
        mode = "0600";
        user = "root";
        group = "root";
      };

      "ssh/ssh_host_ed25519_key.pub" = {
        source = hostSSHPubFile;
        mode = "0644";
        user = "root";
        group = "root";
      };
    };

    sdImage.compressImage = false;

    projectinitiative = {
      hosts.masthead.stormjib.enable = false;
      networking = {
        tailscale.enable = true;
      };
    };

    boot.loader = {
      grub.enable = false;
      systemd-boot.enable = false;  # Disable systemd-boot
      generic-extlinux-compatible.enable = true;  # Enable extlinux bootloader
    };
    console.enable = true;
    environment.systemPackages = with pkgs; [
      libraspberrypi
      raspberrypi-eeprom
    ];

    # Basic networking
    networking.networkmanager.enable = true;
    # Prevent host becoming unreachable on wifi after some time.
    networking.networkmanager.wifi.powersave = false;


    users.users.kylepzak.initialPassword = "changeme";
    users.users.root.initialPassword = "changeme";
  };
}
