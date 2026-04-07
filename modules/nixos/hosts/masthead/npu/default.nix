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
  cfg = config.${namespace}.hosts.masthead.npu;
in
{
  options.${namespace}.hosts.masthead.npu = {
    enable = mkBoolOpt false "Whether to enable the NPU analyzer.";
    package = mkOpt types.package pkgs.${namespace}.npu-analyzer "The NPU analyzer package to use.";
  };

  config = mkIf cfg.enable {
    # Hardware Configuration
    boot.kernelModules = [ "rocket" ];
    hardware.graphics = {
      enable = true;
      extraPackages = [ pkgs.mesa ];
    };

    # Systemd service and network rules
    systemd.services.npu-network-analyzer = {
      description = "NPU Network Traffic Analyzer";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # Network rules to mirror traffic
      preStart = ''
        ${pkgs.nftables}/bin/nft add table inet npu_analyzer || true
        ${pkgs.nftables}/bin/nft add chain inet npu_analyzer forward { type filter hook forward priority 0 \; policy accept \; } || true
        # Prevent adding multiple identical rules if the service restarts
        ${pkgs.nftables}/bin/nft flush chain inet npu_analyzer forward
        ${pkgs.nftables}/bin/nft add rule inet npu_analyzer forward meta nfproto ipv4 log group 100
      '';

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/npu-analyzer";
        Restart = "always";
        RestartSec = "5s";
        # Running as root is typically required for raw sockets / netlink,
        # but could be restricted using capabilities in a real production environment.
        User = "root";
      };

      # Cleanup network rules on stop
      postStop = ''
        ${pkgs.nftables}/bin/nft delete table inet npu_analyzer || true
      '';
    };
  };
}
