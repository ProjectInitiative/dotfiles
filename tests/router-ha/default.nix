{
  pkgs,
  lib,
  ...
}:
let
  routerTest = pkgs.testers.runNixOSTest (
    { pkgs, lib, ... }:
    {
      name = "ha-router-test";

      meta = with pkgs.lib.maintainers; {
        maintainers = [ ];
      };

      # Define specific IP assignments
      nodes = {
        router1 =
          { config, pkgs, ... }:
          {
            virtualisation.vlans = [
              1
              2
              3
            ];

            imports = [
              ../../modules/nixos/hosts/masthead/default.nix
              ../../modules/nixos/hosts/masthead/topsail/default.nix
            ];

            projectinitiative.hosts.masthead.enable = true;
            projectinitiative.hosts.masthead.role = "primary";

            networking.useDHCP = false;
            # Assume wan0 is eth1, lan0 is eth2
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.10";
                prefixLength = 24;
              }
            ];
            networking.interfaces.eth2.ipv4.addresses = [
              {
                address = "172.16.1.2";
                prefixLength = 24;
              }
            ];

            # Add dependencies
            environment.systemPackages = [
              pkgs.iproute2
              pkgs.iptables
            ];
          };

        router2 =
          { config, pkgs, ... }:
          {
            virtualisation.vlans = [
              1
              2
              3
            ];

            imports = [
              ../../modules/nixos/hosts/masthead/default.nix
              ../../modules/nixos/hosts/masthead/stormjib/default.nix
            ];

            projectinitiative.hosts.masthead.enable = true;
            projectinitiative.hosts.masthead.role = "backup";

            networking.useDHCP = false;
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.11";
                prefixLength = 24;
              }
            ];
            networking.interfaces.eth2.ipv4.addresses = [
              {
                address = "172.16.1.3";
                prefixLength = 24;
              }
            ];

            environment.systemPackages = [
              pkgs.iproute2
              pkgs.iptables
            ];
          };

        client1 =
          { config, pkgs, ... }:
          {
            virtualisation.vlans = [ 2 ]; # connected to lan0
            networking.useDHCP = true;
            networking.interfaces.eth1.useDHCP = true;
            # Client connected to VLAN 2 (lan0)
          };

        client2 =
          { config, pkgs, ... }:
          {
            virtualisation.vlans = [ 2 ]; # connected to lan0
            networking.useDHCP = true;
            networking.interfaces.eth1.useDHCP = true;
          };

        isp1 =
          { config, pkgs, ... }:
          {
            virtualisation.vlans = [ 1 ]; # connected to wan0
            networking.useDHCP = false;
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.1";
                prefixLength = 24;
              }
            ];
          };

        isp2 =
          { config, pkgs, ... }:
          {
            virtualisation.vlans = [ 3 ]; # connected to another WAN interface
            networking.useDHCP = false;
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "10.0.0.1";
                prefixLength = 24;
              }
            ];
          };
      };

      testScript = ''
        import time

        start_all()

        router1.wait_for_unit("network.target")
        router2.wait_for_unit("network.target")
        isp1.wait_for_unit("network.target")
        isp2.wait_for_unit("network.target")

        # Wait for the client to get an IP via DHCP
        client1.wait_for_unit("network.target")

        with subtest("VRRP Keepalived Settles"):
            time.sleep(15)  # Wait for Keepalived to negotiate MASTER/BACKUP

            # Router1 should be MASTER and have the VIP (assuming default eth2 lan interface in the module)
            output1 = router1.succeed("ip addr show")
            # VRRP LAN VIP is 172.16.1.1 according to default options
            assert "172.16.1.1" in output1, "Primary router failed to acquire LAN VIP"

            output2 = router2.succeed("ip addr show")
            assert "172.16.1.1" not in output2, "Backup router incorrectly acquired LAN VIP"

        with subtest("DHCP Client acquires IP"):
          client1.wait_until_succeeds("ip addr show | grep 'inet 172.16.1.'")

        with subtest("Client routing via VIP"):
            # The client should have the default route set to the VIP
            client1.succeed("ip route | grep 'default via 172.16.1.1'")

            # We simulate pinging ISP1
            # In a real setup, NAT would be working. We can add a simple NAT rule for testing
            router1.succeed("iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE")
            router1.succeed("sysctl -w net.ipv4.ip_forward=1")

            # Add basic forwarding on client to test routing through gateway
            client1.succeed("ping -c 3 192.168.1.1") # ping ISP1

        with subtest("Failover Scenario: Primary Crashes"):
            router1.crash()

            # Wait for Keepalived on backup to notice and transition to MASTER
            time.sleep(15)

            output2 = router2.succeed("ip addr show")
            assert "172.16.1.1" in output2, "Backup router failed to acquire LAN VIP after primary crash"

        with subtest("Client maintains connectivity via Backup router"):
            # Establish NAT on backup
            router2.succeed("iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE")
            router2.succeed("sysctl -w net.ipv4.ip_forward=1")

            client1.succeed("ping -c 3 192.168.1.1") # ping ISP1 again
      '';
    }
  );
in
routerTest
