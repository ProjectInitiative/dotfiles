# kvmd GPIO override for the PiKVM node — BliSwitch v2 + Digital Loggers EPCR6.
#
# STATUS: EXPERIMENTAL / REFERENCE. The PiKVM currently runs stock PiKVM OS
# (Arch), NOT NixOS, and is managed by hand: the merged YAML lives on-device
# at /etc/kvmd/override.yaml (backup: /etc/kvmd/override.yaml.bak-*). This
# module exists so that when the node is converted to NixOS, the whole
# config is already codified — enable it and kvmd gets the same GPIO view.
#
# What it provisions:
#   - /etc/kvmd/bin/dli-outlet: control script for the EPCR6 (REST API:
#     PUT state for on/off, POST cycle, GET state for LEDs). Auth is the
#     non-admin `pikvm` user over HTTP DIGEST — the password is injected
#     into the kvmd service environment from a sops secret
#     (dli_epcr6_password) via an EnvironmentFile. Never in the repo.
#   - /etc/kvmd/override.yaml rendered from hosts/pikvm/override.yaml.device
#     + hosts/pikvm/epcr6-gpio.yaml semantics (BliSwitch channels + EPCR6
#     cmd/cmdret pseudo-drivers for Astrolabe/Chronometer/Sextant/Octant).
#   - 99-bliswitch-v2.rules: CH340 USB-serial symlink /dev/bliswitch that
#     the BliSwitch v2 driver (xh_hk4401, protocol 1) points at.
# NOTE: DLI client bearer tokens are unsupported on the EPCR6 (see
# hosts/pikvm/README.md auth saga) — do not reintroduce DLI_TOKEN here.
#
# CAUTION: kvmd's `cmd` drivers run as the kvmd user on the PiKVM itself and
# hard-cut power to the DGX Spark nodes (no ATX on those). Off/Cycle buttons
# are confirmation-gated in the UI. Verified DLI outlet map:
# DLI 8=astrolabe, 6=chronometer, 7=sextant, 5=octant.
#
# HARDWARE NOTE: the node is a PiKVM **v3 HAT on RPi4** (kvmd-platform-v3-hdmi-rpi4
# on PiKVM OS). A NixOS conversion needs: kvmd packaged (nixpkgs issue
# #428203 open; community modules hatch01/nixos-pikvm, Gigahawk/nixos-kvmd —
# neither proven on v3-hdmi hardware, WebRTC/janus known broken there),
# nixos-hardware rpi4/CM4 profile, and this module for the GPIO/DLI layer.
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
let
  cfg = config.${namespace}.services.pikvm-kvmd;

  dliOutlet = pkgs.writeShellScript "dli-outlet" ''
    ${builtins.readFile ../../../hosts/pikvm/dli-outlet}
  '';

  # The merged override the device currently runs. If you edit the YAML
  # pieces in hosts/pikvm/, regenerate override.yaml.merged and diff
  # against the device.
  overrideYaml = ../../../hosts/pikvm/override.yaml.merged;
in
{
  options.${namespace}.services.pikvm-kvmd = {
    enable = mkEnableOption "PiKVM kvmd GPIO configuration (BliSwitch v2 + DLI EPCR6)";

    dliHost = mkOption {
      type = types.str;
      default = "http://172.16.1.4";
      description = "Base URL of the Digital Loggers EPCR6";
    };

    dliUser = mkOption {
      type = types.str;
      default = "pikvm";
      description = "EPCR6 username (non-admin, digest; needs outlet grant + non-admin REST enabled on the unit)";
    };

    dliPasswordFile = mkOption {
      type = types.str;
      default = "/run/secrets/dli_epcr6_password";
      description = "Path to file containing the EPCR6 password";
    };
  };

  config = mkIf cfg.enable {
    # sops secret dli_epcr6_password must contain a single systemd
    # EnvironmentFile line: DLI_PASS=<password> (same pattern as
    # mcp_grafana_sa_token in modules/common/encrypted/default.nix).
    sops.secrets.dli_epcr6_password = { };

    # BliSwitch v2: QinHeng CH340 USB-serial adapter -> stable /dev/bliswitch
    # symlink (matches the device's /etc/udev/rules.d/99-bliswitch-v2.rules).
    services.udev.extraRules = ''
      SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", ENV{ID_MODEL}=="USB2.0-Ser_", ENV{ID_REVISION}=="0254", SYMLINK+="bliswitch"
    '';

    environment.etc = {
      "kvmd/override.yaml".source = overrideYaml;
      "kvmd/bin/dli-outlet" = {
        source = dliOutlet;
        mode = "0750";
        user = "root";
        group = "kvmd";
      };
    };

    # kvmd's cmd drivers spawn dli-outlet as child processes of the kvmd
    # service, so they inherit this environment.
    systemd.services.kvmd = {
      environment = {
        DLI_HOST = cfg.dliHost;
        DLI_USER = cfg.dliUser;
      };
      serviceConfig = {
        # File content: DLI_PASS=<password> (sops secret, root-only).
        EnvironmentFile = cfg.dliPasswordFile;
      };
    };

    warnings = [
      "pikvm-kvmd: hard power control for the DGX Spark nodes — Off/Cycle cut power with no graceful shutdown path"
      "pikvm-kvmd: EPCR6 outlet map — DLI 8=astrolabe 6=chronometer 7=sextant 5=octant (verified 2026-11-23); hard power cuts, no graceful path"
    ];
  };
}
