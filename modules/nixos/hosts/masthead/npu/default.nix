{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
let
  cfg = config.${namespace}.hosts.masthead;
in
{
  config = mkIf cfg.enable {
    # Configure NPU support via open-source rocket driver and mesa
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [ mesa ];
    };

    boot.kernelModules = [ "rocket" ];

    # Add NFLOG rule for NPU traffic analysis
    networking.firewall.extraCommands = ''
      # Forward traffic headers to NFLOG group 100 for NPU analysis.
      # Insert at top of FORWARD chain to ensure packets are logged before any ACCEPT/DROP rules.
      iptables -I FORWARD -j NFLOG --nflog-group 100 --nflog-range 128
    '';

    # Deploy the NPU analysis service
    systemd.services.npu-analysis = {
      description = "NPU AI Network Analysis Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.${namespace}.npu-analysis}/bin/npu-analysis";
        Restart = "always";
        RestartSec = "10s";
        # Need root permissions to open NETLINK socket and write to prometheus dir
        User = "root";
        Group = "root";
      };
    };

    # Make the package available in the system
    environment.systemPackages = [ pkgs.${namespace}.npu-analysis ];
  };
}
