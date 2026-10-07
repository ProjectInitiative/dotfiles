# Reusable PiKVM host module — import explicitly from each PiKVM host.
#
#   imports = [
#     inputs.pikvm-flake.nixosModules.default   # kvmd + services + overlay
#     ../../../modules/nixos/hosts/pikvm/host.nix
#   ];
#   projectinitiative.hosts.pikvm = {
#     enable = true;
#     bliSwitch8Port.enable = true;  # only the host wired to the 8-port switch
#   };
#
# NOT auto-imported: it sets services.kvmd.* and nixos-hardware raspberry-pi
# options that only exist when the host also imports hatch01's module (and
# modules/nixos/** default.nix files are auto-global — see default.nix here).
#
# Base (all PiKVM hosts):
#   - config.txt done RIGHT: hatch01 ships its dtoverlays as boot.kernelParams
#     (cmdline.txt), which the Pi firmware ignores. dwc2 (OTG gadget) and the
#     tc358743 HDMI-to-CSI capture are applied via the config.txt API instead.
# Toggle (BliSwitch v2 8-port, one host in the fleet):
#   - kvmd xh_hk4401 driver patched 4→8 channels (same 3-line change the live
#     box applies via /root/bliswitch/patch-xh_hk4401-8port.py; strings verified
#     identical in kvmd 4.217), gpio scheme + view table, /dev/bliswitch udev.
{
  config,
  pkgs,
  namespace,
  lib,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.pikvm;

  # kvmd patched for the BliSwitch v2 8-port switch. The stock xh_hk4401
  # driver tops out at 4 channels:
  #   1. pin validator max 3 -> 7
  #   2. RX regex  G0[1-4] -> G0[1-8] (both protocol framings)
  #   3. TX assert channel <= 3 -> <= 7
  kvmd8port = pkgs.kvmd.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace kvmd/plugins/ugpio/xh_hk4401.py \
        --replace-fail 'valid_number.mk(min=0, max=3, name="XH-HK4401 channel")' \
                       'valid_number.mk(min=0, max=7, name="XH-HK4401 channel")' \
        --replace-fail 'b"AG0[1-4]gA" if self.__protocol == 1 else b"G0[1-4]gA\x00"' \
                       'b"AG0[1-8]gA" if self.__protocol == 1 else b"G0[1-8]gA\x00"' \
        --replace-fail 'assert 0 <= channel <= 3' 'assert 0 <= channel <= 7'
    '';
  });

  # BliSwitch v2 exposes 8 channels, each with an input (led) and an output
  # (button) line — ported from the live box /etc/kvmd/override.yaml
  # (dotfiles-pikvm docs/pikvm/artifacts/override.yaml).
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
  bliswitchScheme = foldl' (acc: n: acc // channel n) { } (range 0 7);

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
in
{
  options.${namespace}.hosts.pikvm = {
    enable = mkBoolOpt false "Whether to configure this host as a PiKVM node.";

    hardwareVersion = mkOpt types.str "v3-hdmi-rpi4" ''
      kvmd platform string (MODEL-VIDEO-BOARD), used for the main config and
      udev rules selection. See pikvm/kvmd configs/kvmd/main/.
    '';

    bliSwitch8Port = {
      enable = mkBoolOpt false ''
        Patch the xh_hk4401 GPIO driver from 4 to 8 channels and install the
        BliSwitch v2 GPIO scheme + udev rule. Only for the host wired to the
        8-port BliSwitch v2; plain single/dual-host PiKVMs leave this off.
      '';
      device = mkOpt types.str "/dev/bliswitch" ''
        Stable udev symlink pointing at the BliSwitch serial controller.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # --- base: firmware config (config.txt) --------------------------------
    # Let the firmware apply overlays to its own DTB instead of extlinux
    # passing a pre-built generation DTB (per nixos-hardware dwc2 guidance).
    # NOTE: the dwc2 OTG overlay itself comes from hatch01's module
    # (configtxt.deviceTreeOverlays.pi4 = dwc2 dr_mode=peripheral) — verified
    # present in the evaluated config; don't add a second one here.
    {
      boot.loader.generic-extlinux-compatible.useGenerationDeviceTree = false;
      hardware.raspberry-pi.configtxt.settings.all = {
        gpu_mem = 128;
        hdmi_force_hotplug = 1;
        dtoverlay = [ "disable-bt" ]; # free PL011 from bluetooth (upstream PiKVM)
      };

      # HDMI-to-CSI capture (tc358743) — first-class nixos-hardware module,
      # replaces the misplaced "dtoverlay=tc358743" kernelParam.
      hardware.raspberry-pi."4".tc358743.enable = true;
    }

    # --- toggle: BliSwitch v2 8-port ----------------------------------------
    (mkIf cfg.bliSwitch8Port.enable {
      services.kvmd.package = kvmd8port;
      services.kvmd.settings = {
        kvmd.gpio = {
          drivers.hk = {
            type = "xh_hk4401";
            protocol = 1;
            device = cfg.bliSwitch8Port.device;
          };
          scheme = bliswitchScheme;
          view.table = bliswitchView;
        };
      };

      # Stable /dev/bliswitch — ported from live box 99-bliswitch-v2.rules
      # (CH340, ID_REVISION 0254 — distinguishes it from the ezcoo CH340,
      # which reports ID_MODEL=USB_Serial / ID_REVISION=0264).
      services.udev.extraRules = ''
        SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", ENV{ID_MODEL}=="USB2.0-Ser_", ENV{ID_REVISION}=="0254", SYMLINK+="bliswitch"
      '';
    })

    # --- common kvmd bits ----------------------------------------------------
    {
      services.kvmd = {
        enable = true;
        hardwareVersion = cfg.hardwareVersion;
      };
    }
  ]);
}
