# surface-laptop-ultra — NixOS hardware module for the Microsoft Surface Laptop Ultra
#
# Hardware (SKU Surface_Laptop_Ultra_2115, UEFI 7.1.0 Project Mu):
#   SoC   NVIDIA N1X "RTX Spark" (GB10 family, aarch64), MediaTek-derived blocks
#   GPU   10de:2e03 — 6144-core Blackwell RTX, unified memory (carveout 4 GiB)
#   NIC   MediaTek MT7925 Wi-Fi/BT
#   Input keyboard MSHW0794 (045E:0CC7, I2C), touchpad ELAN MSHW0734 (04F3:3358),
#         touchscreen/pen MSHW0735 (1FD2:4003) — all I2C HID
#   EC    Surface SAM MSHW0084 over UART NVDA0240 (8250_mtk), platform MSHW0733
#   Audio MT8901 AFE + SoundWire link 0 (NVDA9100): 2x RT1320 amps + RT721 jack
#   Cam   OV02C10 (RGB) + VD55G1 (IR) behind the mt8991 seninf/camsys/CCU block
#
# Everything known about this port comes from teo-casares' write-up
# (gist 8b64949638e1952602a7f435bb34d5b8, vendored in
# vendor/surface-ultra/gist-teo-casares/0-README.md) and ikegam's
# surface-ultra-{camera,misc} repos (vendored, commit-pinned).
#
# Source layout:
#   packages/surface-ultra/kernel-patches  boot.kernelPatches set (linux 7.x)
#   packages/surface-ultra/n1x-carveout    GPU carveout memmap module (load BEFORE nvidia)
#   packages/surface-ultra/n1x-sdw-pads    SoundWire pad drive fix (load BEFORE soundwire_mtk)
#   packages/surface-ultra/surface-ultra-camera       MT8991 ISP modules + libcamera config
#   packages/surface-ultra/surface-ultra-ssam-helper  SSAM UART clock + clients (stock SSAM)
#   packages/surface-ultra/n1x-thermald    skin-temp / SoC-power daemon
#   packages/surface-ultra/surface-ultra-tools        touchpad rebind, backlights, etc.
#
# KNOWN CAVEATS (see vendor/surface-ultra/README.md):
#   - unplug USB4 docks before s2idle suspend (usb4_release=0 is set; tunnel
#     PM untested, a bad SSPM USB4 power request can reset the SoC)
#   - nvidia driver pin: memmap module is what really fixes the carveout; the
#     nvidia-open fallback patch is intentionally NOT carried (Nix rebuilds
#     pin the world instead)
#   - UCM caps RT1320 amp gain at -9 dB: no speaker protection/calibration on
#     Linux, keep volume moderate
#   - webcam needs nvCCU.img extracted from the Windows partition
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hardware.surface-laptop-ultra;

  # The kernel package this module's out-of-tree modules are built against.
  # Default: nixpkgs latest (7.x). Override if you track linux-omarchy.
  kernelPackages = cfg.kernelPackages;

  # Kernel patch set (mutual exclusivity handled inside).
  sluKernelPatches = pkgs.callPackage ./kernel-patches/slu-patches.nix {
    ssamUartViaAggregator = cfg.ssamUartViaAggregator;
  };

  # Out-of-tree module packages, built against the chosen kernel.
  modulePackages = {
    n1x-carveout = pkgs.callPackage ../../../../packages/surface-ultra/n1x-carveout {
      kernel = kernelPackages.kernel;
    };
    n1x-sdw-pads = pkgs.callPackage ../../../../packages/surface-ultra/n1x-sdw-pads {
      kernel = kernelPackages.kernel;
    };
    surface-ultra-camera = pkgs.callPackage ../../../../packages/surface-ultra/surface-ultra-camera {
      kernel = kernelPackages.kernel;
      inherit (cfg) cameraFirmware;
    };
    surface-ultra-ssam-helper = pkgs.callPackage ../../../../packages/surface-ultra/surface-ultra-ssam-helper {
      kernel = kernelPackages.kernel;
    };
  };

  sluTools = pkgs.callPackage ../../../../packages/surface-ultra/surface-ultra-tools { };
  thermald = pkgs.callPackage ../../../../packages/surface-ultra/n1x-thermald { };

  sluKernel = kernelPackages.extend (
    final: prev: {
        kernel = prev.kernel.override {
          kernelPatches = (prev.kernel.passthru.kernelPatches or [ ]) ++ sluKernelPatches;
          # NVPCF/carveout debug + general N1X needs; structured as features
          # rather than one-off trims.
          structuredExtraConfig = with lib.kernel; {
            # Surface Aggregator Module (EC: battery, charger, thermal, fan)
            SURFACE_AGGREGATOR = module;
            SURFACE_AGGREGATOR_REGISTRY = module;
            SURFACE_PLATFORM_PROFILE = module;
            # MT7925 Wi-Fi/BT
            MT7925E = module;
            MT7925U = module;
            BT_MTK = module;
            # I2C HID (keyboard, touchpad, touchscreen)
            I2C_HID_ACPI = module;
            HID_MULTITOUCH = module;
            # SoundWire audio (MT8901 AFE + RT1320/RT721)
            SND_SOC_MT8901 = module;
            SOUNDWIRE_MTK = module;
            SND_SDW_AMPS = module;
            SND_SOC_RT1320_SDW = module;
            SND_SOC_RT721_SDCA_SDW = module;
            # Serial (SAM EC link, NVDA0240 on 8250_mtk)
            SERIAL_8250_MTK = module;
            # Sensor collection (skin temp via SSAM; thermal daemon)
            SURFACE_TEMP = module;
            SURFACE_FAN = module;
          };
        };
  }
);
in
{
  options.${namespace}.hardware.surface-laptop-ultra = {
    enable = mkBoolOpt false "Enable the Microsoft Surface Laptop Ultra (NVIDIA N1X) hardware configuration";

    kernelPackages = mkOpt types.raw (pkgs.linuxPackages_latest or pkgs.linuxPackages) "Kernel package set to patch and build modules against (linux 7.x)";

    ssamUartViaAggregator = mkOpt types.bool false ''
      Use the surface_aggregator baud-halving quirk (kernel patch 0002) instead
      of the 8250_mtk clock-frequency fix (0001). Exactly one is applied either
      way. Prefer the default (0001, upstreamable).
    '';

    useSsamHelperModules = mkOpt types.bool true ''
      Use ikegam's ssam-helper out-of-tree modules (n1x_ssam_uartclk +
      n1x_ssam_clients) with STOCK in-tree SSAM drivers, instead of the
      kernel-patch approach. This is the update-resilient choice: nothing
      in-tree is replaced. When true, kernel patches 0001/0002/0003 are
      disabled automatically.
    '';

    enableCamera = mkOpt types.bool true "Build and wire the MT8991 camera ISP modules (needs CCU firmware for a working camera)";
    cameraFirmware = mkOpt (types.nullOr types.path) null "Store path to nvCCU.img (extract from the Windows partition; see vendor/surface-ultra/README.md)";
    enableThermald = mkOpt types.bool true "Enable n1x-thermald (skin ≤ 45 °C via CPU freq capping; emergency at 55.5/62 °C)";
    enableTools = mkOpt types.bool true "Install the userspace service scripts (touchpad rebind, backlights, sdw settle, key repeat)";

    # Kernel command line. Defaults mirror the proven Omarchy N1X setup.
    extraKernelParams = mkOpt (types.listOf types.str) [ ] "Extra kernel command line parameters appended to the SLU set";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.useSsamHelperModules -> !cfg.ssamUartViaAggregator;
        message = "surface-laptop-ultra: ssam-helper modules replace the need for the SSAM kernel patches; disable kernelPatches 0001-0003 (they are auto-disabled when useSsamHelperModules = true, but ssamUartViaAggregator was explicitly requested too).";
      }
    ];

    # ------------------------------------------------------------------
    # Kernel & boot
    # ------------------------------------------------------------------
    boot = {
      kernelPackages = sluKernel;

      # Out-of-tree modules. Load order is enforced via modprobe softdeps
      # below (n1x_carveout_memmap before nvidia; sdw_pad_drive before
      # soundwire_mtk; n1x_ssam_uartclk before surface_aggregator).
      extraModulePackages =
        with modulePackages;
        [
          n1x-carveout
          n1x-sdw-pads
          surface-ultra-ssam-helper
        ]
        ++ optional cfg.enableCamera modulePackages.surface-ultra-camera;

      # GRUB, NOT Limine: Limine 12.9.3 resets the Project Mu firmware before
      # drawing anything (likely init_memmap() + ConnectController(recursive);
      # limine #521 territory). GRUB from the proven USB-stick image works.
      loader.grub = {
        enable = true;
        efiSupport = true;
        device = mkDefault "nodev";
        efiInstallAsRemovable = mkDefault true; # Project Mu NVRAM writes are unreliable
        copyKernels = true;
      };
      loader.efi.canTouchEfiVariables = mkDefault false;

      # Proven N1X kernel command line (teo-casares, Omarchy discussion #15885):
      #   acpi_osi=!             — five ACPI devices (SVP0/SSPM/HFRP/NH1X/NMAP)
      #                            hide themselves from Windows 2022 OSI; without
      #                            this, USB/I2C/SPI (keyboard, touchpad, USB) are DEAD
      #   modprobe.blacklist=gpio_keys — phantom Volume Down from floating MSHW0040
      #                            pins 40/41 floods the console (side buttons lost
      #                            unless n1x-power-button handles pin 46)
      #   module_blacklist=nouveau — Blackwell GB10 needs nvidia-open
      #   pci=hpbussize=0x20     — Omarchy N1X support (USB4 hotplug bridge sizing)
      #   mem_sleep_default=s2idle — only supported sleep on this firmware
      #   console=tty0 acpi=nospcr — display/console plumbing quirks
      #   initramfs_async=0 plymouth.enable=0 zswap.enabled=0 — boot reliability
      # NOTE: power_wrap_drv.usb4_release=0 deliberately NOT set (validated
      # only on ASUS ProArt P14 / Dell XPS 16; untested and risky here).
      kernelParams =
        [
          "acpi_osi=!"
          "modprobe.blacklist=gpio_keys"
          "module_blacklist=nouveau"
          "pci=hpbussize=0x20"
          "mem_sleep_default=s2idle"
          "console=tty0"
          "acpi=nospcr"
          "initramfs_async=0"
          "zswap.enabled=0"
        ]
        ++ cfg.extraKernelParams;

      # S0ix for the NVIDIA GPU (Windows parity for s2idle).
      extraModprobeConfig = ''
        options nvidia NVreg_EnableS0ixPowerManagement=1
        # Load-order contracts:
        options nvidia NVreg_OpenRmEnableUnsupportedGpus=1
        softdep nvidia pre: n1x_carveout_memmap
        softdep soundwire_mtk pre: sdw_pad_drive
        softdep surface_aggregator pre: n1x_ssam_uartclk
      '';

      kernelModules = [
        "n1x_carveout_memmap"
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
      ];
    };

    # ------------------------------------------------------------------
    # GPU / video
    # ------------------------------------------------------------------
    services.xserver.videoDrivers = mkDefault [ "nvidia" ];
    hardware.nvidia = mkIf (config.hardware.nvidia ? open) {
      open = mkDefault true;
      nvidiaSettings = mkDefault false;
      # Power management off until suspend/resume is verified on this platform.
      powerManagement.enable = mkDefault false;
    };
    hardware.graphics.enable = mkDefault true;

    # ------------------------------------------------------------------
    # Input: udev, libinput, hwdb
    # ------------------------------------------------------------------
    services.udev.extraRules = ''
      # [usb4] keep the USB4 tunnel root ports (NVIDIA 10de:22cf) out of runtime
      # suspend; while suspended, dock devices behind them do not enumerate.
      # (Approach from teo-casares; rules file vendored from surface-ultra-misc.)
      ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x22cf", ATTR{power/control}="on"

      # [touchpad] bind the ELAN 04F3:3358 touchpad to the hid-multitouch class
      # used by Windows Precision Touchpads (palm rejection via Confidence bit).
      ACTION=="add", SUBSYSTEM=="hid", ATTRS{vendor}=="0x04f3", ATTRS{product}=="0x3358", ATTR{driver}!="hid-multitouch", RUN+="${getExe sluTools}/../bin/n1x-touchpad-ptp"

      # [key-repeat] keyboard key-release reports arrive 20-145 ms late (I2C
      # stall); raise the kernel TTY autorepeat delay to 500 ms for this device.
      ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", ATTRS{name}=="MSHW0794:00 045E:0CC7 Keyboard", RUN+="${sluTools}/bin/kbd-repeat-delay $devnode 500"
    '';

    services.udev.extraHwdb = ''
      # [buttons] floating MSHW0040 pins 40/41 report "Volume Down" held forever.
      # Neutralise them; the real power button is handled separately (gpio_keys
      # is blacklisted, soc_button_array is x86-only).
      evdev:input:b0018v045Ep0CC7*
        KEYBOARD_KEY_70046 = reserved
    '';

    environment.etc."libinput/local-overrides.quirks".text = ''
      # Surface Laptop Ultra (N1X) ELAN touchpad: advertises pressure 0-2048 but
      # real touches report ~20-40, so libinput's pressure threshold (~204)
      # rejects every touch. Ignore the pressure axes; fall back to plain
      # contact detection. (Upstream candidate: INPUT_PROP_PRESSUREPAD, as for
      # Elan 04F3:3355.)
      [Surface Laptop Ultra Touchpad]
      MatchUdevType=touchpad
      MatchBus=i2c
      MatchVendor=0x04F3
      MatchProduct=0x3358
      AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
    '';

    # ------------------------------------------------------------------
    # Audio: UCM profile (RT1320 gain capped at -9 dB) + SoundWire settle
    # ------------------------------------------------------------------
    # Custom UCM profile wired via /etc/alsa/ucm2/conf.d — ALSA merges this
    # over the alsa-ucm-conf package's /share/alsa/ucm2 tree. The card name
    # must match the machine-table entry from kernel patch 0005.
    environment.etc = {
      "alsa/ucm2/conf.d/mt8901-soundwir/MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf".source =
        "${../../../../vendor/surface-ultra/gist-teo-casares/MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf}";
      "alsa/ucm2/conf.d/mt8901-soundwir/HiFi-surface-laptop-ultra.conf".source =
        "${../../../../vendor/surface-ultra/gist-teo-casares/HiFi-surface-laptop-ultra.conf}";
    };

    # Base UCM tree (ucm2/links.conf etc.) must be present for the custom
    # conf.d profile to resolve; alsa-ucm-conf is added to systemPackages
    # in the userspace section below.

    systemd.services.n1x-sdw-settle = mkIf cfg.enableTools {
      description = "One soft SoundWire link reset after the card appears";
      after = [ "sound.target" ];
      wantedBy = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${sluTools}/bin/n1x-sdw-settle";
      };
    };

    # ------------------------------------------------------------------
    # Power / thermal
    # ------------------------------------------------------------------
    systemd.services.n1x-thermald = mkIf cfg.enableThermald {
      description = "Surface Laptop Ultra (N1X) skin temperature / SoC power controller";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${thermald}/bin/n1x-thermald";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment.N1XTHERMALD_PATH = "${thermald}/bin/n1x-thermald";
    };

    # Sleep hook: disable wakeup on the I2C keyboard / touchpad / power button
    # for lid-closed suspends (bag wakeups), restore on resume. Vendored from
    # surface-ultra-misc/suspend/surface-ultra-lid-wakeup; the gist variant
    # targets MSHW0794:00 specifically — the hook below is the union.
    powerManagement.powerDownCommands = ''
      grep -qs closed /proc/acpi/button/lid/*/state && {
        for d in /sys/bus/i2c/devices/i2c-MSHW0794:00 /sys/bus/i2c/devices/i2c-MSHW0734:00 /sys/bus/platform/devices/MSHW0040:00; do
          [ -w "$d/power/wakeup" ] && echo disabled > "$d/power/wakeup"
        done
      }
    '';
    powerManagement.resumeCommands = ''
      for d in /sys/bus/i2c/devices/i2c-MSHW0794:00 /sys/bus/i2c/devices/i2c-MSHW0734:00 /sys/bus/platform/devices/MSHW0040:00; do
        [ -w "$d/power/wakeup" ] && echo enabled > "$d/power/wakeup"
      done
    '';

    # ------------------------------------------------------------------
    # Tools, services & userspace
    # ------------------------------------------------------------------
    environment.systemPackages =
      optional cfg.enableTools sluTools
      ++ optional cfg.enableThermald thermald
      ++ optional cfg.enableCamera pkgs.libcamera
      ++ [ pkgs.alsa-ucm-conf ];

    # n1x-touchpad-ptp rebind at boot (idempotent; skipped if kernel patch 0004
    # already bound the device as MT_CLS_WIN_8 — the script detects this).
    systemd.services.n1x-touchpad-ptp = mkIf cfg.enableTools {
      description = "Rebind ELAN 04F3:3358 touchpad as MT_CLS_WIN_8";
      after = [ "systemd-udevd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${sluTools}/bin/n1x-touchpad-ptp";
        RemainAfterExit = true;
      };
    };

    systemd.packages = optionals cfg.enableTools [
      sluTools
    ];
  };
}
