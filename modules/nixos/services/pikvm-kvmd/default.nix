# kvmd GPIO override for the PiKVM node — BliSwitch v2 + Digital Loggers EPCR6.
#
# STATUS: EXPERIMENTAL / REFERENCE. The PiKVM currently runs stock PiKVM OS
# (Arch), NOT NixOS, and is managed by hand: the merged YAML lives on-device
# at /etc/kvmd/override.yaml (backup: /etc/kvmd/override.yaml.bak-*). This
# module exists so that when the node is converted to NixOS, the whole
# config is already codified — enable it and kvmd gets the same GPIO view.
#
# What it provisions:
#   - /etc/kvmd/bin/dli-outlet: control script for the EPCR6
#     (legacy outlet?N=ON|OFF|CCL for control, REST-then-/status-bitmap for
#     state). The password is injected into the kvmd service environment
#     from a sops secret (dli_epcr6_password) via an EnvironmentFile —
#     never stored in the script or repo.
#   - /etc/kvmd/override.yaml rendered from hosts/pikvm/override.yaml.device
#     + hosts/pikvm/epcr6-gpio.yaml semantics (BliSwitch channels + EPCR6
#     cmd/cmdret pseudo-drivers for Astrolabe/Chronometer/Sextant/Octant).
#
# CAUTION: kvmd's `cmd` drivers run as the kvmd user on the PiKVM itself and
# hard-cut power to the DGX Spark nodes (no ATX on those). Off/Cycle buttons
# are confirmation-gated in the UI.
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
      description = "EPCR6 username (non-admin; needs outlet grant in Setup > Users)";
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
      "pikvm-kvmd: EPCR6 outlet map (3=Astrolabe 4=Chronometer 5=Sextant 6=Octant) is an unverified guess"
    ];
  };
}
