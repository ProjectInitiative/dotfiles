{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.system.console-info.ip-display;
in
{
  options.${namespace}.system.console-info.ip-display = with types; {
    enable = mkBoolOpt false "Whether or not to enable dynamic IP address display on the console.";
    updateInterval =
      mkOpt str "5m"
        "Interval at which to update the IP address display (e.g., '5m' for 5 minutes).";
  };

  config = mkIf cfg.enable {

    # Create the Python script
    environment.etc."local/bin/get_ip_addresses.py".source = pkgs.writeScript "get_ip_addresses.py" ''
      #!/usr/bin/env python3

      import re
      import subprocess

      def get_ip_addresses(ip_output):
          ipv4_pattern = re.compile(r'inet (\d+\.\d+\.\d+\.\d+/\d+)')
          ipv6_pattern = re.compile(r'inet6 ([a-fA-F0-9:]+/\d+)')

          ipv4_addresses = []
          ipv6_addresses = []

          for line in ip_output.splitlines():
              ipv4_match = ipv4_pattern.search(line)
              ipv6_match = ipv6_pattern.search(line)

              if ipv4_match:
                  ipv4_addresses.append(ipv4_match.group(1))
              if ipv6_match:
                  ipv6_addresses.append(ipv6_match.group(1))

          return ipv4_addresses, ipv6_addresses

      def main():
          # Run the `ip a` command and capture its output
          ip_output = subprocess.run(['${pkgs.iproute2}/bin/ip', 'a'], capture_output=True, text=True).stdout

          # Get the IP addresses
          ipv4_addresses, ipv6_addresses = get_ip_addresses(ip_output)

          # Print the results
          print("IPv4 Addresses:")
          for ip in ipv4_addresses:
              print(ip)

          print("\nIPv6 Addresses:")
          for ip in ipv6_addresses:
              print(ip)

      if __name__ == "__main__":
          main()
    '';

    # Add the script to the system's PATH
    environment.systemPackages = [
      pkgs.python3
      (pkgs.writeScriptBin "get-ips" ''
        #!/bin/sh
        exec /etc/local/bin/get_ip_addresses.py
      '')
    ];

    # # Replace the static helpLine with the output of the Python script
    # services.getty.helpLine = mkForce ''
    #   Network Information:
    #   ${lib.removeSuffix "\n" (builtins.readFile (pkgs.runCommand "get-ip-info" {} ''
    #     ${pkgs.python3}/bin/python /etc/local/bin/get_ip_addresses.py > $out
    #   ''))}
    # '';

    # Systemd service to update the helpLine dynamically
    systemd.services.update-getty-helpline = {
      description = "Update Getty HelpLine with Network Information";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        # ExecStart = "${pkgs.python3}/bin/python3 /etc/local/bin/get_ip_addresses.py > var/run/issue";
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.python3}/bin/python3 etc/local/bin/get_ip_addresses.py > /var/run/issue'";
        # Type = "oneshot";
      };
    };

    environment.etc."issue".source = "/var/run/issue";

    # Systemd timer to run the service periodically
    systemd.timers.update-getty-helpline = {
      description = "Timer for updating Getty HelpLine with Network Information";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m"; # Run 1 minute after boot
        OnUnitActiveSec = cfg.updateInterval; # Run at the specified interval
        Unit = "update-getty-helpline.service";
      };
    };
  };
}
