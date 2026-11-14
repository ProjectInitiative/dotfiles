# surface-ultra — Microsoft Surface Laptop Ultra (NVIDIA RTX Spark N1X, aarch64)
#
# Functionally identical to thinkpad (daily-driver laptop, GNOME, dev suite)
# but on the N1X SoC, which needs a LOT of patches and custom modules — all
# wired through ${namespace}.hardware.surface-laptop-ultra
# (modules/nixos/hardware/surface-laptop-ultra/).
#
# Provisioning status: configuration-first (no hardware yet, expected next
# week). TODOs are marked per-item for the first-boot checklist:
#   - hardware-configuration: generate from the real disk (nixos-generate-config)
#   - secrets.enc.yaml: copy thinkpad's shape, re-encrypt for the new host key
#   - restic backup targets: decide disk layout first
#   - kbd repeat: gnome/kde side uses repeat_delay 500 in desktop settings too
{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  ...
}:
with lib;
with lib.${namespace};
{
  imports = [
    # Placeholder until the real disk is scanned; a generated
    # hardware-configuration.nix replaces this at install time (see TODO).
    ./hardware-configuration.nix

    # NOTE: the SLU hardware module (modules/nixos/hardware/surface-laptop-ultra)
    # is auto-imported by snowfall into every host — no explicit import needed;
    # everything below is gated on hardware.surface-laptop-ultra.enable.
  ];

  networking.hostName = "surface-ultra";

  ${namespace} = {
    # ------------------------------------------------------------------
    # SLU hardware module tuning
    # ------------------------------------------------------------------
    hardware.surface-laptop-ultra = {
      enable = true;
      kernelPackages = pkgs.linuxPackages_latest; # linux 7.x — target of all patches

      # Stock SSAM drivers + ikegam's out-of-tree helper modules (update-resilient;
      # nothing in-tree replaced). Flip to false + ssamUartViaAggregator = true to
      # use the kernel-patch approach instead.
      useSsamHelperModules = true;

      # TODO(hardware): extract nvCCU.img from the Windows partition with
      # vendor/surface-ultra/surface-ultra-camera/firmware/extract-from-windows.sh,
      # import it (sops or plain store path), then set cameraFirmware.
      enableCamera = true;
      cameraFirmware = null;

      enableThermald = true; # skin ≤ 45 °C; keep enabled until NVPCF 3.0 lands upstream
      enableTools = true;
    };

    # ------------------------------------------------------------------
    # Desktop & suites (mirrors thinkpad)
    # ------------------------------------------------------------------
    settings = {
      stateVersion = "26.05";
    };

    encrypted.nix-signing = enabled;

    system = {
      displaylink.enable = false;
      nix-config = enabled;
    };

    gui = {
      gnome = enabled;
    };

    services = {
      power-profile-manager = enabled;
      # TPM untested on this platform — revisit after first boot.
      tpm = enabled;
    };

    suites = {
      loft = {
        enable = true;
        enableClient = true;
        enableServer = true;
      };
      attic = {
        enableClient = mkForce false;
      };
      development = enabled;
    };
  };

  home-manager = {
    backupFileExtension = "backup";
    users.kylepzak.${namespace} = {
      suites = {
        development.enable = true;
      };
    };
  };

  # ------------------------------------------------------------------
  # Networking / misc (mirrors thinkpad)
  # ------------------------------------------------------------------
  networking.networkmanager.enable = true;

  virtualisation = {
    docker.enable = true;
    spiceUSBRedirection.enable = true;
  };

  environment.systemPackages = with pkgs; [
    smartmontools
    nvme-cli
    mtr
    vlc
    wireshark
    networkmanagerapplet
    minicom
    usbutils
    android-tools

    alsa-utils
    pavucontrol

    yubikey-manager
    yubioath-flutter

    # Camera diagnostics (SLU webcam is libcamera/PipeWire based)
    libcamera
    v4l-utils
  ];

  # Visage face auth: the SLU IR camera (VD55G1) is NOT a UVC node — it needs
  # the camera stack. TODO(hardware): evaluate visage-on-libcamera after the
  # camera firmware is in place; until then password/fingerprint only.
  # services.visage = { ... };

  # Fingerprint reader: TODO(hardware) — identify the device on first boot
  # (likely Goodix I2C); enable services.fprintd once known.

  services.fwupd.enable = true;
  services.printing.enable = true;

  users.users.kylepzak.extraGroups = [
    "tss"
    "adbusers"
    "dialout"
    "networkmanager"
  ];

  # ------------------------------------------------------------------
  # Audio (PipeWire, mirrors thinkpad; SLU UCM comes from the SLU module)
  # ------------------------------------------------------------------
  security.rtkit.enable = true;
  services.pipewire = {
    enable = mkForce true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.extraConfig.bluetoothEnhancements = {
      "monitor.bluez.properties" = {
        "bluez5.codecs" = "[ sbc sbc_xq aac ldac aptx aptx_hd ]";
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [
          "hsp_hs"
          "hsp_ag"
          "hfp_hf"
          "hfp_ag"
          "a2dp_sink"
          "a2dp_source"
        ];
      };
    };
  };
  services.pulseaudio.enable = false;
  hardware.alsa.enable = true;

  # MT7925 Wi-Fi/BT firmware (in linux-firmware; make sure it's included)
  hardware.firmware = [ pkgs.linux-firmware ];

  # Console key repeat also uses the 500 ms workaround via the SLU udev rule;
  # desktop-side repeat settings (GNOME) should set delay 500 ms / rate 40 too —
  # TODO(desktop): set via gsettings once on hardware
  # (org.gnome.desktop.peripherals.keyboard delay=500 rate=40).

  # ------------------------------------------------------------------
  # TODO(hardware, first-boot checklist)
  # ------------------------------------------------------------------
  # 1. Generate hardware-configuration.nix from the real NVMe (Micron 4600).
  # 2. Verify `acpi_osi=!` took effect: USB/I2C/SPI alive (keyboard, touchpad).
  # 3. Check /var/lib/n1x-dkms-guard equivalent — all modules built against
  #    the booted kernel version.
  # 4. upower -d → BAT1 + ADP1 present (SSAM up).
  # 5. wpctl status → speakers, jack, mic array endpoints.
  # 6. brightnessctl -l → nvidia_0::lcd_backlight + surface::kbd_backlight.
  # 7. UNPLUG any USB4 dock before testing suspend (s2idle; untested upstream).
  # 8. nvidia-smi + glmark2-wayland sanity; check no vmap WARNs in dmesg.
}
