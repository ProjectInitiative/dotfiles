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
  cfg = config.${namespace}.hosts.masthead;
  qosCfg = cfg.qos;

  applyQosScript = pkgs.writeShellScript "apply-metered-qos" ''
    #!/usr/bin/env bash
    # Clear existing tc and nftables rules
    ${pkgs.iproute2}/bin/tc qdisc del dev ${qosCfg.wanInterface} root 2>/dev/null || true
    ${pkgs.nftables}/bin/nft delete table inet metered_qos 2>/dev/null || true

    # Only apply on metered role when active
    if [ "$1" = "${qosCfg.meteredRole}" ]; then
      echo "Applying metered QoS profile on ${qosCfg.wanInterface}..."

      # Setup root qdisc
      ${pkgs.iproute2}/bin/tc qdisc add dev ${qosCfg.wanInterface} root handle 1: htb default 99

      # Setup nftables table and chain for marking in the forward hook
      ${pkgs.nftables}/bin/nft add table inet metered_qos
      ${pkgs.nftables}/bin/nft add chain inet metered_qos forward { type filter hook forward priority 0 \; policy accept \; }

      ${concatStringsSep "\n" (mapAttrsToList (name: tier: ''
        ${optionalString (!tier.blocked) ''
          # Class for ${name}
          ${pkgs.iproute2}/bin/tc class add dev ${qosCfg.wanInterface} parent 1: classid 1:${toString tier.priority} htb rate ${tier.rate} ceil ${tier.ceil}
          ${pkgs.iproute2}/bin/tc qdisc add dev ${qosCfg.wanInterface} parent 1:${toString tier.priority} handle ${toString tier.priority}0: sfq perturb 10
          ${pkgs.iproute2}/bin/tc filter add dev ${qosCfg.wanInterface} protocol ip parent 1: prio 1 handle ${toString tier.priority} fw flowid 1:${toString tier.priority}
        ''}
      '') qosCfg.tiers)}

      ${concatStringsSep "\n" (mapAttrsToList (name: tier: ''
        ${concatMapStringsSep "\n" (subnet: ''
          ${if tier.blocked then ''
            # Drop traffic for ${subnet} via nftables (only when destined out WAN)
            ${pkgs.nftables}/bin/nft add rule inet metered_qos forward oifname ${qosCfg.wanInterface} ip saddr ${subnet} drop
          '' else ''
            # Mark traffic for ${subnet} via nftables (only when destined out WAN)
            ${pkgs.nftables}/bin/nft add rule inet metered_qos forward oifname ${qosCfg.wanInterface} ip saddr ${subnet} meta mark set 0x${toString tier.priority}
          ''}
        '') tier.subnets}

        ${concatMapStringsSep "\n" (mac: ''
          ${if tier.blocked then ''
            # Drop traffic for MAC ${mac} via nftables (only when destined out WAN)
            ${pkgs.nftables}/bin/nft add rule inet metered_qos forward oifname ${qosCfg.wanInterface} ether saddr ${mac} drop
          '' else ''
            # Mark traffic for MAC ${mac} via nftables (only when destined out WAN)
            ${pkgs.nftables}/bin/nft add rule inet metered_qos forward oifname ${qosCfg.wanInterface} ether saddr ${mac} meta mark set 0x${toString tier.priority}
          ''}
        '') tier.macs}
      '') qosCfg.tiers)}

      # Default catch-all filter to something slow
      ${pkgs.iproute2}/bin/tc class add dev ${qosCfg.wanInterface} parent 1: classid 1:99 htb rate 1mbit ceil 5mbit
      ${pkgs.iproute2}/bin/tc qdisc add dev ${qosCfg.wanInterface} parent 1:99 handle 990: sfq perturb 10
    else
      echo "Standard connection active, no metered QoS applied."
    fi
  '';

  removeQosScript = pkgs.writeShellScript "remove-metered-qos" ''
    #!/usr/bin/env bash
    ${pkgs.iproute2}/bin/tc qdisc del dev ${qosCfg.wanInterface} root 2>/dev/null || true
    ${pkgs.nftables}/bin/nft delete table inet metered_qos 2>/dev/null || true
  '';

in
{
  options.${namespace}.hosts.masthead.qos = {
    enable = mkBoolOpt false "Enable dynamic QoS and metered WAN traffic shaping.";
    wanInterface = mkOpt types.str "wan0" "The WAN interface to apply QoS to.";
    meteredRole = mkOpt types.str "backup" "The router role that corresponds to the metered connection.";
    tiers = mkOpt (types.attrsOf (types.submodule {
      options = {
        priority = mkOpt types.int 1 "Priority tier id.";
        rate = mkOpt types.str "1mbit" "Rate limit (e.g., '10mbit').";
        ceil = mkOpt types.str "1mbit" "Ceil limit (e.g., '20mbit').";
        subnets = mkOpt (types.listOf types.str) [] "Subnets mapping to this tier.";
        macs = mkOpt (types.listOf types.str) [] "MAC addresses mapping to this tier.";
        blocked = mkBoolOpt false "Whether this tier is entirely blocked on metered connection.";
      };
    })) {
      critical = { priority = 10; rate = "50mbit"; ceil = "100mbit"; subnets = [ "192.168.10.0/24" ]; };
      standard = { priority = 20; rate = "10mbit"; ceil = "50mbit"; subnets = [ "192.168.21.0/24" ]; };
      throttled = { priority = 30; rate = "1mbit"; ceil = "5mbit"; subnets = [ "192.168.22.0/24" ]; };
      blocked = { priority = 40; blocked = true; subnets = [ "192.168.30.0/24" ]; };
    } "QoS Tiers.";

    applyScript = mkOpt types.package applyQosScript "The generated script to apply QoS.";
    removeScript = mkOpt types.package removeQosScript "The generated script to remove QoS.";
  };

  config = mkIf (cfg.enable && qosCfg.enable) {
    environment.systemPackages = [ pkgs.iproute2 pkgs.nftables ];
  };
}
