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
#     PUT state for on/off, POST cycle, GET state for LEDs). Auth is a
#     scoped DLI client access token (bearer) — outlets 5-8 only — injected
#     into the kvmd service environment from a sops secret
#     (dli_epcr6_token) via an EnvironmentFile. No admin password on the
#     node, ever.
#   - /etc/kvmd/override.yaml rendered from hosts/pikvm/override.yaml.device
#     + hosts/pikvm/epcr6-gpio.yaml semantics (BliSwitch channels + EPCR6
#     cmd/cmdret pseudo-drivers for Astrolabe/Chronometer/Sextant/Octant).
#
# CAUTION: kvmd's `cmd` drivers run as the kvmd user on the PiKVM itself and
# hard-cut power to the DGX Spark nodes (no ATX on those). Off/Cycle buttons
# are confirmation-gated in the UI. Verified DLI outlet map:
# DLI 8=astrolabe, 6=chronometer, 7=sextant, 5=octant.
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

    dliClient = mkOption {
      type = types.str;
      default = "pikvm";
      description = "DLI client access-token name (bearer auth)";
    };

    dliTokenFile = mkOption {
      type = types.str;
      default = "/run/secrets/dli_epcr6_token";
      description = "Path to file containing the DLI client access token";
    };
  };

  config = mkIf cfg.enable {
    # sops secret dli_epcr6_token must contain a single systemd
    # EnvironmentFile line: DLI_TOKEN=<token> (same pattern as
    # mcp_grafana_sa_token in modules/common/encrypted/default.nix).
    sops.secrets.dli_epcr6_token = { };

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
        DLI_CLIENT = cfg.dliClient;
      };
      serviceConfig = {
        # File content: DLI_TOKEN=<token> (sops secret, root-only).
        EnvironmentFile = cfg.dliTokenFile;
      };
    };

    warnings = [
      "pikvm-kvmd: hard power control for the DGX Spark nodes — Off/Cycle cut power with no graceful shutdown path"
      "pikvm-kvmd: EPCR6 outlet map — DLI 8=astrolabe 6=chronometer 7=sextant 5=octant (verified 2026-11-23); hard power cuts, no graceful path"
    ];
  };
}
