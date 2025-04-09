{
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;

let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.networking.mellanox;

  # Type for a single Mellanox interface
  interfaceType = types.submodule {
    options = {

      device = mkOption {
        type = types.str;
        example = "Mellanox Connect X-3";
        description = "Device model name";
      };

      pciAddress = mkOption {
        type = types.str;
        example = "0000:05:00.0";
        description = "PCI address of the Mellanox card";
      };

      nics = mkOption {
        type = types.listOf types.str;
        example = [
          "enp5s0"
          "enp5s0d1"
          "bond0"
          "vmbr4"
        ];
        description = "List of network interfaces to bring up";
      };

      mlnxPorts = mkOption {
        type = types.listOf types.str;
        example = [
          "1"
          "2"
        ];
        description = "List of Mellanox ports to configure";
      };

      mode = mkOption {
        type = types.str;
        default = "eth";
        example = "eth";
        description = "Mode to set for the Mellanox ports (eth, ib, etc.)";
      };
    };
  };

  # Convert interfaces to the format expected by the Python script
  interfacesJson = builtins.toJSON {
    interfaces = map (iface: {
      device = iface.device;
      pci_address = iface.pciAddress;
      nics = iface.nics;
      mlnx_ports = iface.mlnxPorts;
      mode = iface.mode;
    }) cfg.interfaces;
  };

  interfacesJsonFile = pkgs.writeTextFile {
    name = "mellanox-interfaces.json";
    text = interfacesJson;
  };

  # Create a proper Python package with the setup script
  mellanoxSetupScript = pkgs.python3Packages.buildPythonApplication {
    pname = "setup-mellanox";
    version = "1.0.0";

    src = ./.;

    # No build required
    format = "other";

    # Specify Python dependencies
    propagatedBuildInputs = with pkgs; [
      bash
      iproute2
    ];

    # Simple installation
    installPhase = ''
      install -Dm755 setup-mellanox.py $out/bin/setup-mellanox
    '';
  };

in
{
  options.${namespace}.networking.mellanox = {
    enable = mkEnableOption "Mellanox configuration service";

    interfaces = mkOption {
      type = types.listOf interfaceType;
      default = [ ];
      example = [
        {
          device = "Mellanox Connect X-3";
          pciAddress = "0000:05:00.0";
          nics = [
            "enp5s0"
            "enp5s0d1"
            "bond0"
            "vmbr4"
          ];
          mlnxPorts = [
            "1"
            "2"
          ];
          mode = "eth";
        }
      ];
      description = "List of Mellanox interfaces to configure";
    };
  };

  config = mkIf cfg.enable {
    # Add the mellanox setup script to the system packages
    environment.systemPackages = [ mellanoxSetupScript ];

    # Create systemd service to run the script at boot
    systemd.services.setup-mellanox = {
      description = "Configure Mellanox network cards";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      before = [ "network.target" ];
      path = with pkgs; [
        iproute2
        bash
      ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${mellanoxSetupScript}/bin/setup-mellanox --config ${interfacesJsonFile}";
        RemainAfterExit = true;
      };
    };
  };
}
