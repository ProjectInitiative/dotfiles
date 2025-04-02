# modules/router/kernel.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.kernel;
in
{
  options.${namespace}.router.kernel = with types; {
    extraModules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional kernel modules to load.";
    };
    extraSysctl = mkOption {
      type = types.attrsOf types.anything; # Allow any valid sysctl value type
      default = { };
      description = "Additional custom sysctl settings.";
    };
  };

  config = mkIf cfg.enable {
    boot = {
      kernelModules = [
        # Base modules needed for routing/firewalling/NAT/VLANs
        "nf_nat"          # General NAT connection tracking helper
        "nf_conntrack"    # Connection tracking core
        # "iptable_nat"     # Replaced by nf_nat generally
        # "iptable_filter"  # Loaded by default usually
        "nf_reject_ipv4"  # For REJECT target
        "nf_reject_ipv6"  # For REJECT target (if using ip6tables)
        "ip_tables"       # Core iptables module
        "8021q"           # VLAN support
      ] ++ moduleCfg.extraModules;

      # Kernel sysctl settings beyond basic forwarding (already in default.nix)
      kernel.sysctl = {
        # Recommended security/performance settings for a router
        "net.ipv4.tcp_syncookies" = 1; # Mitigate SYN floods
        "net.ipv4.conf.all.rp_filter" = 1; # Enable strict reverse path filtering
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.all.log_martians" = 1; # Log packets with impossible source addresses
        "net.ipv4.conf.default.log_martians" = 1;

        # IPv6 settings beyond basic forwarding/RA (already in default.nix)
        "net.ipv6.conf.all.accept_ra" = 0; # Don't accept RAs on internal interfaces by default
        "net.ipv6.conf.default.accept_ra" = 0;
        "net.ipv6.conf.all.autoconf" = 0; # Don't autoconfigure addresses internally
        "net.ipv6.conf.default.autoconf" = 0;
        "net.ipv6.conf.all.use_tempaddr" = 0; # Routers typically don't need temporary addresses

        # Adjust WAN interface specifically if needed (done in networking.nix now)
        # "net.ipv6.conf.${cfg.wanInterface}.accept_ra" = mkIf cfg.enableIPv6 2; # Accept even if forwarding
        # "net.ipv6.conf.${cfg.wanInterface}.autoconf" = mkIf cfg.enableIPv6 1;

        # Add custom settings from config
      } // moduleCfg.extraSysctl;
    };
  };
}
