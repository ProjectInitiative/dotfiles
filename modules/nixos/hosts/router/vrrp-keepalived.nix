# modules/nixos/hosts/base-router/router/vrrp-keepalived.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  sops, # Need sops if password is encrypted
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.vrrp;
in
{
  options.${namespace}.router.vrrp = with types; {
    enable = mkBoolOpt true "Whether to enable VRRP (Keepalived) for high availability.";

    # VRRP base ID and priority can be adjusted per-router in host config
    virtualRouterIdBase = mkOption {
      type = types.int;
      default = 10;
      description = "Base VRRP Virtual Router ID (incremented for each VLAN)";
    };

    priority = mkOption {
      type = types.int;
      default = 100; # Primary typically > 100, Backup < 100
      description = "VRRP priority for this router (higher wins). Set based on routerRole.";
    };

    # Password should ideally come from sops or similar
    authPassFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the VRRP authentication password.";
      example = ''sops.secrets."keepalived_vrrp_password".path'';
    };
    authPass = mkOption {
       type = types.nullOr types.str;
       default = null;
       description = "VRRP authentication password (plain text, use authPassFile instead).";
    };

    # Peer address derived automatically from managementVlan IPs based on role
    # peerAddress = mkOption { type = types.str; description = "IP address of the peer router on the management VLAN"; };

    keaFailoverPort = mkOption {
      type = types.port;
      default = 647; # Default Kea HA port
      description = "Port used for Kea DHCP failover communication (if enabled).";
    };

    notifyMasterScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command or script path to run when this node becomes MASTER.";
    };
    notifyBackupScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command or script path to run when this node becomes BACKUP.";
    };
    notifyFaultScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command or script path to run when this node enters FAULT state.";
    };
  };

  config = mkIf (cfg.enable && moduleCfg.enable) {

    assertions = [
        { assertion = moduleCfg.authPass != null || moduleCfg.authPassFile != null;
          message = "Either vrrp.authPass or vrrp.authPassFile must be set when VRRP is enabled.";
        }
        { assertion = !(moduleCfg.authPass != null && moduleCfg.authPassFile != null);
          message = "Cannot set both vrrp.authPass and vrrp.authPassFile.";
        }
    ];

    _module.args.vrrpPassword = if moduleCfg.authPassFile != null
        then builtins.readFile moduleCfg.authPassFile
        else moduleCfg.authPass;

    # Automatically determine peer address
    _module.args.peerAddress = if cfg.routerRole == "primary"
        then cfg.managementVlan.backupIp
        else cfg.managementVlan.primaryIp;

    # Automatically set priority based on role
    _module.args.vrrpPriority = if cfg.routerRole == "primary"
        then moduleCfg.priority # Use the configured priority for primary
        else moduleCfg.priority - 50; # Backup is lower (adjust logic as needed)

    services.keepalived = {
      enable = true;
      # global_defs might not be needed if router_id is not globally required by scripts
      # global_defs = { router_id = "router_${cfg.routerRole}"; };

      vrrpScripts = {
          # Example check script (e.g., check WAN connectivity)
          # chk_wan = {
          #   script = "${pkgs.runtimeShell} -c 'ping -c 1 8.8.8.8 &> /dev/null'";
          #   interval = 2; # seconds
          #   fall = 2; # require 2 failures to fall
          #   rise = 2; # require 2 successes to rise
          #   weight = 10; # Adjust priority by this amount on failure
          # };
      };

      vrrpInstances = let
         mkInstance = { name, vlanId, virtualIp, networkInfo }: {
            # Instance name must be unique on the host
            # Using VLAN ID ensures uniqueness
            state = if cfg.routerRole == "primary" then "MASTER" else "BACKUP";
            interface = if vlanId == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString vlanId}";
            virtualRouterId = moduleCfg.virtualRouterIdBase + vlanId; # Unique VRID per VLAN/subnet
            priority = config._module.args.vrrpPriority;
            advertInt = 1; # seconds
            authentication = {
                authType = "PASS";
                authPass = config._module.args.vrrpPassword;
            };
            # unicastPeer = [ config._module.args.peerAddress ]; # Use unicast for direct communication
            virtualIPAddresses = [
                { ip = virtualIp; # IPv4 VIP
                  # prefix = networkInfo.prefixLength; # Not needed for address object
                }
                # Add IPv6 VIPs here if used
                # { ip = "YOUR_IPV6_VIP"; dev = if vlanId == 1 then cfg.lanInterface else "..."; }
            ];

            # Scripts to run on state change
            notifyMaster = moduleCfg.notifyMasterScript;
            notifyBackup = moduleCfg.notifyBackupScript;
            notifyFault = moduleCfg.notifyFaultScript;

            # Track scripts (optional, adjust priority based on script success/failure)
            # trackScript = [ "chk_wan" ];
         };

         mgmtInstance = mkInstance {
            name = "MGMT";
            vlanId = cfg.managementVlan.id;
            virtualIp = cfg.managementVlan.virtualIp;
            networkInfo = config._module.args.parsedNetworks.management;
         };

         vlanInstances = listToAttrs (map (vlan: {
            name = "VLAN_${toString vlan.id}"; # Keepalived instance name needs to be attr name
            value = mkInstance {
                name = vlan.name; # Descriptive name for logs etc.
                vlanId = vlan.id;
                virtualIp = vlan.virtualIp;
                networkInfo = findFirst (pn: pn.id == vlan.id) null config._module.args.parsedNetworks.vlans;
            };
         }) cfg.vlans);

      in { "MGMT_VRRP" = mgmtInstance; } // vlanInstances; # Combine mgmt and VLAN instances
    };

    # Firewall rules for VRRP (Protocol 112)
    networking.firewall.allowedProtocols = [ "vrrp" ]; # Protocol 112
    # Or more specific rules if needed:
    # networking.firewall.extraCommands = ''
    #   iptables -A INPUT -p vrrp -s ${config._module.args.peerAddress} -j ACCEPT
    #   iptables -A OUTPUT -p vrrp -d ${config._module.args.peerAddress} -j ACCEPT
    # '';

    # Packages
    environment.systemPackages = with pkgs; [ keepalived ];
  };
}
