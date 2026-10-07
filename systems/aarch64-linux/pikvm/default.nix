# PiKVM node (Raspberry Pi 4 Model B) — NixOS conversion of the Arch ARM box.
#
# Discovery (2026-10-06): docs/pikvm/discovery-2026-10-06.md — live box runs
# Arch ARM + kvmd 4.215-1, platform v3-hdmi-rpi4, BliSwitch v2 8-port via kvmd's
# stock xh_hk4401 driver (config-only, NO kvmd source patches needed).
#
# Base: hatch01/nixos-pikvm (kvmd 4.217, active) via inputs.pikvm-flake — its
# module imports nixos-hardware raspberry-pi-4 + nginx and wires janus/ustreamer.
#
# Install path (TODO): SD image build or kexec — the Arch install currently
# controls the 8-host BliSwitch and must not be taken down casually.
{
  config,
  pkgs,
  inputs,
  namespace,
  lib,
  ...
}:
let
  # BliSwitch v2 8 channels — each channel has an input (led) and an output
  # (button) line on the xh_hk4401 driver. Ported from
  # /etc/kvmd/override.yaml (docs/pikvm/artifacts/override.yaml).
  channel =
    n:
    {
      "ch${toString n}_led" = {
        driver = "hk";
        pin = n;
        mode = "input";
      };
      "ch${toString n}_button" = {
        driver = "hk";
        pin = n;
        mode = "output";
        switch = false;
      };
    };
  bliswitchScheme = lib.foldl' (acc: n: acc // channel n) { } (lib.range 0 7);

  bliswitchView = [
    [ "#Capstan1" "ch0_led" "ch0_button" ]
    [ "#Capstan2" "ch1_led" "ch1_button" ]
    [ "#Capstan3" "ch2_led" "ch2_button" ]
    [ "#Astrolabe" "ch3_led" "ch3_button" ]
    [ "#Chronometer" "ch4_led" "ch4_button" ]
    [ "#Sextant" "ch5_led" "ch5_button" ]
    [ "#Octant" "ch6_led" "ch6_button" ]
    [ "#INPUT 8" "ch7_led" "ch7_button" ]
  ];

  deployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRiGsoimWWFcrnXlN8+AcdkZba43h1D26D5Ep3KDDYe";
in
{
  imports = [
    # hatch01/nixos-pikvm — provides services.kvmd (+ kvmd overlay, nginx
    # module, nixos-hardware raspberry-pi-4 import inside the module).
    inputs.pikvm-flake.nixosModules.default
  ];

  # Common modules enable zfs on all hosts; the Pi SD install doesn't want it
  # (same pattern as dcc-ex / wharfmaster).
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking.hostName = "pikvm";

  # --- kvmd ---------------------------------------------------------------
  services.kvmd = {
    enable = true;
    # Live box: kvmd-platform-v3-hdmi-rpi4.
    hardwareVersion = "v3-hdmi-rpi4";

    # TODO: sops secret before first real deploy — the module falls back to the
    # package default htpasswd when null.
    # passwordFile = config.sops.secrets."kvmd/htpasswd".path;

    # BliSwitch v2 (8-port) GPIO switching — kvmd stock xh_hk4401 driver.
    settings = {
      kvmd.gpio = {
        drivers.hk = {
          type = "xh_hk4401";
          protocol = 1;
          device = "/dev/bliswitch";
        };
        scheme = bliswitchScheme;
        view.table = bliswitchView;
      };
    };
  };

  # --- udev rules (ported from live box, see artifacts/udev-rules.txt) -----
  services.udev.extraRules = ''
    # e52c on USB path 1-1.2.1
    KERNEL=="ttyUSB*", KERNELS=="1-1.2.1", SYMLINK+="e52c"
    # Ezcoo KVM serial on USB path 1-1.4 (CH340)
    KERNEL=="ttyUSB*", KERNELS=="1-1.4", SYMLINK+="ezcoo"
    # pikvm-atx RP2040 firmware (0232:0232)
    ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="0232", ATTRS{idProduct}=="0232", SYMLINK+="pikvmatx"
    # BliSwitch v2 (CH340 rev 0254) — stable /dev/bliswitch
    SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", ENV{ID_MODEL}=="USB2.0-Ser_", ENV{ID_REVISION}=="0254", SYMLINK+="bliswitch"
  '';

  # --- network (live: eth0 static mgmnt, VLAN 2 dhcp) ----------------------
  networking = {
    useDHCP = lib.mkDefault false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.1.85";
        prefixLength = 24;
      }
    ];
    defaultGateway = "172.16.1.1";
    # TODO: verify fleet DNS policy (resolved is enabled by the tailscale module)
    nameservers = [
      "172.16.1.1"
      "1.1.1.1"
    ];
    vlans."eth0.2" = {
      id = 2;
      interface = "eth0";
    };
    interfaces."eth0.2".useDHCP = true;
  };

  # Tailnet — the live box is a tagged device (100.117.169.9). No sops key
  # provisioned yet: authenticate interactively with `tailscale up` on first
  # boot, then flip useSops on once the key exists.
  # (single ${namespace} block — Nix forbids two dynamic attrs with the same key)
  ${namespace} = {
    networking.tailscale = {
      enable = true;
      useSops = false;
      ephemeral = false; # permanent tagged device, must survive reboots
    };

    # --- host identity ------------------------------------------------------
    settings.stateVersion = lib.mkForce "26.05";
  };

  # --- storage -------------------------------------------------------------
  # SD card layout (fresh NixOS install): p1 = firmware (FAT32), p2 = root.
  # Matches the standard NixOS aarch64 SD image labels.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
  };
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Live box kept msd/pst on a dedicated SD partition; start on root fs and
  # dedicate a partition later if needed.
  systemd.tmpfiles.rules = [
    "d /var/lib/kvmd/msd 0755 - - -"
    "d /var/lib/kvmd/pst 0755 - - -"
  ];

  # --- access --------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users.kylepzak = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ deployKey ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ deployKey ];
}
