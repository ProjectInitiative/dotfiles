# PiKVM node (Raspberry Pi 4 Model B) — the 8-port BliSwitch v2 host.
#
# Discovery (2026-10-07): docs/pikvm/discovery-2026-10-06.md — live box runs
# Arch ARM + kvmd 4.215-1, platform v3-hdmi-rpi4. The reusable PiKVM module
# (modules/nixos/hosts/pikvm/host.nix) owns kvmd/OTG/BliSwitch logic; this
# file is only host-specific identity, network, and access.
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
  deployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRiGsoimWWFcrnXlN8+AcdkZba43h1D26D5Ep3KDDYe";
in
{
  imports = [
    # hatch01/nixos-pikvm: services.kvmd (+ kvmd-otg/otgnet/ipmi/janus/media/
    # pst/vnc/oled units), kvmd overlay (provides pkgs.kvmd), nginx module,
    # nixos-hardware rpi4. Imported per-host so the overlay stays off other
    # machines (modules/nixos/** default.nix files are auto-global).
    inputs.pikvm-flake.nixosModules.default
    # Reusable PiKVM module: config.txt (OTG dwc2 + tc358743 capture) and the
    # BliSwitch v2 8-port toggle. Its options live here, not auto-global.
    ../../../modules/nixos/hosts/pikvm/host.nix
  ];

  # Common modules enable zfs on all hosts; the Pi SD install doesn't want it
  # (same pattern as dcc-ex / wharfmaster).
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking.hostName = "pikvm";

  # Single dynamic block — Nix forbids two top-level ${namespace} attributes.
  ${namespace} = {
    hosts.pikvm = {
      enable = true;
      # This is the box wired to the 8-port BliSwitch v2.
      bliSwitch8Port.enable = true;
    };

    # Network — live box: eth0 static mgmnt 172.16.1.85/24, VLAN 2 dhcp
    # (192.168.1.220), default via 172.16.1.1.
    networking = {
      tailscale = {
        enable = true;
        # TODO: provision sops key (tailscale_auth_key) for this host, then
        # flip useSops on. Until then authenticate with `tailscale up`.
        useSops = false;
        ephemeral = false; # permanent tagged device (100.117.169.9)
      };
    };

    settings.stateVersion = lib.mkForce "26.05";
  };

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

  # --- udev: this box's serial peripherals (from artifacts/udev-rules.txt) --
  # Port paths assume the same VIA Labs hub topology as the live install.
  services.udev.extraRules = ''
    # e52c on USB path 1-1.2.1
    KERNEL=="ttyUSB*", KERNELS=="1-1.2.1", SYMLINK+="e52c"
    # Ezcoo KVM serial on USB path 1-1.4 (CH340)
    KERNEL=="ttyUSB*", KERNELS=="1-1.4", SYMLINK+="ezcoo"
    # pikvm-atx RP2040 firmware (0232:0232)
    ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="0232", ATTRS{idProduct}=="0232", SYMLINK+="pikvmatx"
  '';

  # --- SD card layout (fresh NixOS install): p1 firmware, p2 root ----------
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
  };
  boot.loader.grub.enable = false;
  # NOTE: /var/lib/kvmd/{msd,pst} mounts are declared by the kvmd module
  # (LABEL=PIMSD / LABEL=PIPST, nofail) — partition the SD accordingly at
  # install time or the first boot warns.

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
