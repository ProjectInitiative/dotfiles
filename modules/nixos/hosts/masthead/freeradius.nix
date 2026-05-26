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
  cfg = config.${namespace}.hosts.masthead.freeradius;

  raddbDir = pkgs.runCommand "masthead-raddb" {
    preferLocalBuild = true;
  } ''
    cp -r ${pkgs.freeradius}/etc/raddb/* $out/
    chmod -R u+w $out

    # Replace clients.conf with one that includes runtime-generated config
    cat > $out/clients.conf << 'CLIENTS'
    # Static clients
    client localhost {
      ipaddr = 127.0.0.1
      secret = testing123
    }
    # Runtime-generated client configs (from sops secrets, etc.)
    $INCLUDE /var/lib/radiusd/clients.conf
    CLIENTS

    mkdir -p $out/log
  '';

  clientsWithSecret = filter (c: c.secret != null) cfg.clients;
  clientsWithFile = filter (c: c.secretFile != null) cfg.clients;
in
{
  options.${namespace}.hosts.masthead.freeradius = with types; {
    enable = mkBoolOpt false "Whether to enable FreeRADIUS on this node";

    clients = mkOption {
      type = types.listOf (types.submodule {
        options = {
          shortname = mkOption {
            type = types.str;
            description = "Short name for this NAS/client";
          };
          ipaddr = mkOption {
            type = types.str;
            description = "IP address or CIDR of the NAS/client";
          };
          secret = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Shared secret inline. Use secretFile for sops-managed secrets.";
          };
          secretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to file containing the shared secret (e.g., sops secret path like /run/secrets/radius-brocade)";
          };
        };
      });
      default = [ ];
      description = "RADIUS clients (NAS devices, switches, APs)";
    };

    macAuth = mkOption {
      type = types.listOf (types.submodule {
        options = {
          mac = mkOption {
            type = types.str;
            description = "MAC address (lowercase, no separators)";
            example = "aabbccddeeff";
          };
          vlanId = mkOption {
            type = types.int;
            default = 18;
            description = "VLAN ID to assign to this device";
          };
        };
      });
      default = [ ];
      description = "MAC authentication bypass entries mapping MAC to VLAN";
    };

    users = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Username";
          };
          password = mkOption {
            type = types.str;
            description = "Password (cleartext)";
          };
          vlanId = mkOption {
            type = types.int;
            default = 18;
            description = "VLAN ID to assign on successful auth";
          };
        };
      });
      default = [ ];
      description = "User accounts for PEAP/MS-CHAPv2 or PAP authentication";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [ 1812 1813 ];

    environment.systemPackages = [ pkgs.freeradius ];

    systemd.services.freeradius = {
      description = "FreeRADIUS high-performance RADIUS server";
      after = [ "network.target" ] ++ optional (clientsWithFile != [ ]) "sops-nix.service";
      wants = optional (clientsWithFile != [ ]) "sops-nix.service";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.freeradius ];

      preStart = let
        inlineConfs = concatStringsSep "\n" (map (c: ''
          client ${c.shortname} {
            ipaddr = ${c.ipaddr}
            secret = ${c.secret}
            shortname = ${c.shortname}
          }
        '') clientsWithSecret);

        fileConfs = concatStringsSep "\n" (map (c: ''
          client ${c.shortname} {
            ipaddr = ${c.ipaddr}
            secret = __RADIUS_SECRET_${c.shortname}__
            shortname = ${c.shortname}
          }
        '') clientsWithFile);

        subs = concatStringsSep "\n" (map (c: ''
          sed -i "s/__RADIUS_SECRET_${c.shortname}__/$(cat ${c.secretFile})/g" /var/lib/radiusd/clients.conf
        '') clientsWithFile);
      in ''
        mkdir -p /var/lib/radiusd
        cat > /var/lib/radiusd/clients.conf << 'CLIENTS'
        ${inlineConfs}
        ${fileConfs}
        CLIENTS
        ${subs}
        chmod 600 /var/lib/radiusd/clients.conf
      '';

      serviceConfig = {
        ExecStart = "${pkgs.freeradius}/sbin/radiusd -d ${raddbDir} -f";
        ExecReload = "${pkgs.freeradius}/sbin/radiusd -d ${raddbDir} -X";
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
