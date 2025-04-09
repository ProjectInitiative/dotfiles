# VRRP configuration using keepalived
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.networking.vrrp;
  # Assuming router config is now under the namespace
  routerCfg = config.${namespace}.router;

  # Helper function to generate keepalived configuration blocks
  generateVrrpInstance = name: instance: {
    name = name;
    content = ''
      virtual_router_id ${toString instance.virtualRouterId}
      priority ${toString instance.priority}
      state ${if instance.priority == 255 then "MASTER" else "BACKUP"}
      interface ${instance.interface}
      use_vmac ${if instance.useVmac then "vmac_${instance.interface}" else ""}
      ${optionalString instance.useVmac ''
        vmac_xmit_base
      ''}
      ${optionalString (instance.advertisementInterval != null) "advert_int ${toString instance.advertisementInterval}"}
      authentication {
        auth_type ${if instance.authPassFile != null then "PASS" else "AH"}
        ${optionalString (instance.authPassFile != null) "auth_pass_file ${instance.authPassFile}"}
        # TODO: Add support for AH authentication if needed
      }
      virtual_ipaddress {
        ${concatStringsSep "\n" (map (ip: "${ip.address}/${toString ip.prefixLength}") instance.virtualIPs)}
      }
      ${optionalString (instance.preemptDelay != null) "preempt_delay ${toString instance.preemptDelay}"}

      ${optionalString (instance.notifyMaster != null) "notify_master \"${instance.notifyMaster}\""}
      ${optionalString (instance.notifyBackup != null) "notify_backup \"${instance.notifyBackup}\""}
      ${optionalString (instance.notifyFault != null) "notify_fault \"${instance.notifyFault}\""}
      ${optionalString (instance.notifyStop != null) "notify_stop \"${instance.notifyStop}\""}
      ${optionalString (instance.notifyScript != null) "notify \"${instance.notifyScript}\""}

      ${optionalString (instance.smtpAlert) "smtp_alert"}

      # Track interfaces for state changes
      ${optionalString (instance.trackInterfaces != [ ]) ''
        track_interface {
          ${concatStringsSep "\n" instance.trackInterfaces}
        }
      ''}

      # Track scripts for state changes based on script exit status
      ${optionalString (instance.trackScripts != { }) (
        concatMapStringsSep "\n" (name: script: ''
          track_script {
            ${name}
          }
        '') (mapAttrsToList (name: script: { inherit name; value = script; }) instance.trackScripts)
      )}
    '';
  };

  generateVrrpScript = name: script: {
    name = name;
    content = ''
      script "${script.script}"
      interval ${toString script.interval}
      timeout ${toString script.timeout}
      ${optionalString (script.weight != null) "weight ${toString script.weight}"}
      ${optionalString (script.user != null) "user ${script.user}"}
      ${optionalString (script.initFail) "init_fail"}
      ${optionalString (script.rise != null) "rise ${toString script.rise}"}
      ${optionalString (script.fall != null) "fall ${toString script.fall}"}
    '';
  };

in
{
  options.networking.vrrp = {
    enable = mkEnableOption "Enable VRRP using keepalived";

    globalDefs = {
      enableScriptSecurity = mkOption {
        type = types.bool;
        default = false;
        description = "If set, scripts are executed as the user specified by `script_user`. If not set (default), scripts execute as root.";
      };
      scriptUser = mkOption {
        type = types.nullOr types.str;
        default = null; # Typically 'keepalived_script' or similar
        description = "User to run scripts under if `enableScriptSecurity` is true. Group defaults to the user's primary group.";
      };
      enableDynamicInterfaces = mkOption {
        type = types.bool;
        default = false;
        description = "Allow interfaces specified in the configuration to be added/removed while keepalived is running.";
      };
      # Add other relevant global_defs options here as needed
      routerId = mkOption {
        type = types.str;
        default = config.networking.hostName; # Default to the system hostname
        description = "VRRP Router ID. Must be unique for each machine.";
      };
      vrrpControls = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to the FIFO used by the vrrp command line utility.";
      };
      # ... other global defs
    };

    staticRoutes = mkOption {
      type = types.listOf (types.submodule {
        options = {
          src = mkOption { type = types.str; description = "Source IP address"; };
          dst = mkOption { type = types.str; description = "Destination network (e.g., 192.168.100.0/24)"; };
          gw = mkOption { type = types.str; description = "Gateway IP address"; };
          dev = mkOption { type = types.nullOr types.str; default = null; description = "Device to route through"; };
          metric = mkOption { type = types.nullOr types.int; default = null; description = "Route metric"; };
        };
      });
      default = [ ];
      description = "Static routes to be configured by keepalived.";
      example = [{ src = "10.0.0.1"; dst = "192.168.5.0/24"; gw = "10.0.0.254"; dev = "eth1"; metric = 100; }];
    };

    staticRules = mkOption {
      type = types.listOf (types.submodule {
        options = {
          src = mkOption { type = types.str; description = "Source IP address/network"; };
          dst = mkOption { type = types.nullOr types.str; default = null; description = "Destination IP address/network"; };
          fwmark = mkOption { type = types.nullOr types.int; default = null; description = "Firewall mark"; };
          table = mkOption { type = types.str; description = "Routing table identifier (name or number)"; };
          priority = mkOption { type = types.nullOr types.int; default = null; description = "Rule priority"; };
        };
      });
      default = [ ];
      description = "Static IP rules (policy routing) to be configured by keepalived.";
      example = [{ src = "192.168.2.10/32"; table = "T1"; priority = 100; }];
    };

    vrrpScripts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          script = mkOption { type = types.str; description = "Path to the script or command to execute."; example = "/usr/local/bin/check_service.sh"; };
          interval = mkOption { type = types.int; default = 2; description = "Interval in seconds to run the script."; };
          timeout = mkOption { type = types.nullOr types.int; default = null; description = "Timeout in seconds for the script execution."; };
          weight = mkOption { type = types.nullOr types.int; default = null; description = "Weight to add/subtract from priority based on script success/failure."; };
          rise = mkOption { type = types.nullOr types.int; default = null; description = "Required number of successes before considered UP."; };
          fall = mkOption { type = types.nullOr types.int; default = null; description = "Required number of failures before considered DOWN."; };
          user = mkOption { type = types.nullOr types.str; default = null; description = "User to run the script as (requires globalDefs.enableScriptSecurity)."; };
          initFail = mkOption { type = types.bool; default = false; description = "Assume script is failed on startup."; };
        };
      });
      default = { };
      description = "Named scripts that can be tracked by VRRP instances.";
      example = {
        chk_haproxy = { script = "killall -0 haproxy"; interval = 2; weight = 2; fall = 2; rise = 2; };
      };
    };

    vrrpInstances = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          virtualRouterId = mkOption { type = types.ints.between 1 255; description = "Unique ID (1-255) for the virtual router instance. Must be the same across all nodes in the VRRP group."; };
          priority = mkOption { type = types.ints.between 1 255; description = "Priority (1-255). Highest priority becomes MASTER. 255 usually for IP address owner."; };
          interface = mkOption { type = types.str; description = "Interface to run VRRP on."; example = "eth0"; };
          useVmac = mkOption { type = types.bool; default = false; description = "Use a virtual MAC address for this instance."; };
          advertisementInterval = mkOption { type = types.nullOr types.int; default = null; description = "VRRP advertisement interval in seconds."; };
          authPassFile = mkOption { type = types.nullOr types.path; default = null; description = "Path to a file containing the password for PASS authentication. Ensure permissions are secure."; example = config.sops.secrets."keepalived_vrrp_password".path; };
          # authType = mkOption { type = types.enum [ "PASS" "AH" ]; default = "PASS"; description = "Authentication type."; }; # Simplified: derive from authPassFile
          virtualIPs = mkOption {
            type = types.listOf (types.submodule {
              options = {
                address = mkOption { type = types.str; description = "Virtual IP address."; };
                prefixLength = mkOption { type = types.int; description = "Prefix length for the virtual IP."; };
                # dev = mkOption { type = types.nullOr types.str; default = null; description = "Interface for the VIP (defaults to instance interface)."; };
                # scope = mkOption { type = types.nullOr types.str; default = null; description = "Scope for the VIP (e.g., link, global)."; };
              };
            });
            default = [ ];
            description = "List of virtual IP addresses managed by this instance.";
            example = [ { address = "192.168.1.254"; prefixLength = 24; } ];
          };
          preemptDelay = mkOption { type = types.nullOr types.int; default = null; description = "Seconds to delay preemption if a higher priority router comes online."; };
          trackInterfaces = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of interfaces to monitor. If any go down, priority is reduced.";
            example = [ "eth1" "eth2" ];
          };
          trackScripts = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "List of names (from vrrpScripts) of scripts to track.";
            example = [ "chk_haproxy" ];
          };
          notifyMaster = mkOption { type = types.nullOr types.str; default = null; description = "Script to run when transitioning to MASTER state."; };
          notifyBackup = mkOption { type = types.nullOr types.str; default = null; description = "Script to run when transitioning to BACKUP state."; };
          notifyFault = mkOption { type = types.nullOr types.str; default = null; description = "Script to run when transitioning to FAULT state."; };
          notifyStop = mkOption { type = types.nullOr types.str; default = null; description = "Script to run when VRRP instance stops."; };
          notifyScript = mkOption { type = types.nullOr types.str; default = null; description = "Script to run for any state transition."; };
          smtpAlert = mkOption { type = types.bool; default = false; description = "Enable SMTP alerts for state transitions (requires global SMTP settings)."; };
          # Add other instance-specific options like nopreempt, garp intervals, etc.
        };
      });
      default = { };
      description = "Configuration for individual VRRP instances.";
      example = {
        VI_1 = {
          virtualRouterId = 51;
          priority = 100;
          interface = "eth0";
          authPassFile = "/path/to/vrrp_password";
          virtualIPs = [ { address = "10.0.0.1"; prefixLength = 24; } ];
          trackInterfaces = [ "eth1" ];
        };
      };
    };
    # Potentially add options for virtual_server blocks if keepalived is also used for LVS load balancing
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.keepalived ];

    # Ensure keepalived service runs after network is up
    systemd.services.keepalived = {
      description = "Keepalived VRRP and Load Balancing Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Reload configuration without restarting the daemon
      reloadIfChanged = true;

      serviceConfig = {
        ExecStart = "${pkgs.keepalived}/sbin/keepalived --dont-fork --dump-config --log-console --log-detail --vrrp";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        KillMode = "process";
        Restart = "on-failure";
        # Consider capabilities or user/group if not running as root
        # AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_NET_BIND_SERVICE" ];
        # User = "keepalived"; # Requires setting up user/group
        # Group = "keepalived";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_NET_BIND_SERVICE" "CAP_SETUID" "CAP_SETGID" "CAP_CHOWN" ]; # Adjust based on scriptUser/enableScriptSecurity
        SecureBits = "keep-caps";
      };
    };

    # Generate keepalived.conf
    environment.etc."keepalived/keepalived.conf" = {
      text = ''
        global_defs {
          ${optionalString (cfg.globalDefs.routerId != null) "router_id ${cfg.globalDefs.routerId}"}
          ${optionalString cfg.globalDefs.enableScriptSecurity "enable_script_security"}
          ${optionalString (cfg.globalDefs.scriptUser != null) "script_user ${cfg.globalDefs.scriptUser}"}
          ${optionalString cfg.globalDefs.enableDynamicInterfaces "enable_dynamic_interfaces"}
          ${optionalString (cfg.globalDefs.vrrpControls != null) "vrrp_controls ${cfg.globalDefs.vrrpControls}"}
          # Add other global defs serialization here
        }

        # Static routes configuration
        ${optionalString (cfg.staticRoutes != []) ''
          static_routes {
            ${concatMapStringsSep "\n" (route: ''
              ${route.src} ${optionalString (route.dev != null) "dev ${route.dev}"} to ${route.dst} via ${route.gw} ${optionalString (route.metric != null) "metric ${toString route.metric}"}
            '') cfg.staticRoutes}
          }
        ''}

        # Static rules configuration
        ${optionalString (cfg.staticRules != []) ''
          static_rules {
            ${concatMapStringsSep "\n" (rule: ''
              ${rule.src} ${optionalString (rule.dst != null) "to ${rule.dst}"} ${optionalString (rule.fwmark != null) "fwmark ${toString rule.fwmark}"} table ${rule.table} ${optionalString (rule.priority != null) "priority ${toString rule.priority}"}
            '') cfg.staticRules}
          }
        ''}

        # VRRP script definitions
        ${concatMapStringsSep "\n\n" (name: script:
          let generated = generateVrrpScript name script;
          in "vrrp_script ${generated.name} {\n${generated.content}\n}"
        ) (mapAttrsToList (n: v: v) cfg.vrrpScripts)}


        # VRRP instance definitions
        ${concatMapStringsSep "\n\n" (name: instance:
          let generated = generateVrrpInstance name instance;
          in "vrrp_instance ${generated.name} {\n${generated.content}\n}"
        ) (mapAttrsToList (n: v: v) cfg.vrrpInstances)}

        # TODO: Add virtual_server configuration generation if needed
      '';
      mode = "0640";
      # group = "keepalived"; # If using a dedicated group
    };

    # Firewall rules for VRRP (IP Protocol 112)
    # Allow VRRP traffic between routers on the relevant interfaces.
    # This assumes VRRP runs on interfaces involved in routing (LAN/WAN/DMZ).
    # It might need refinement based on specific VRRP instance interfaces.
    # networking.firewall.allowedIPProtocols = mkIf cfg.enable [ "vrrp" ];

    # Allow multicast if needed by VRRP (usually not required for standard operation)
    # networking.firewall.extraInputRules = ''
    #   ip protocol vrrp accept
    # '';
    # networking.firewall.extraOutputRules = ''
    #   ip protocol vrrp accept
    # '';

    # Ensure necessary kernel modules are loaded
    boot.kernelModules = [ "ip_vrrp" ]; # Might be needed for some keepalived features or older kernels

    # Sysctl settings recommended or required by keepalived/VRRP
    boot.kernel.sysctl = {
      # Allow non-local binding for virtual IPs
      "net.ipv4.ip_nonlocal_bind" = mkDefault 1;
      # Consider IPv6 settings if using VRRPv6
      # "net.ipv6.conf.all.accept_ra" = 2; # Example, adjust as needed
    };

    # If using sops for secrets like authPassFile
    sops.secrets = let
      vrrpSecrets = filterAttrs (n: v: v.authPassFile != null && hasPrefix "/run/secrets" v.authPassFile) cfg.vrrpInstances;
      extractSecretName = path: baseNameOf (removePrefix "/run/secrets/" path);
    in mapAttrs' (n: v: nameValuePair (extractSecretName v.authPassFile) {
      # Assuming the sops secret name matches the base name of the file path
      # mode = "0400"; # Keepalived needs to read this
      # user = "keepalived"; # If running keepalived as a specific user
    }) vrrpSecrets;

  };
}
