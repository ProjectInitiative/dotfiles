{ lib }:
let
  controlAddresses = {
    astrolabe = "172.16.4.54";
    chronometer = "172.16.4.55";
    sextant = "172.16.4.56";
    octant = "172.16.4.57";
  };

  # The switchless fabric is declared once. Each link has exactly two endpoints;
  # linksFor derives reciprocal peer identity, addresses, and MACs so those
  # values cannot drift between host configurations.
  #
  # 4-node ring (astrolabe → octant → chronometer → sextant → astrolabe).
  # Each chassis QSFP connector (P0/P1) exposes TWO 100G rails on separate
  # PCIe paths: P0 = enp1s0f0np0 + enP2p1s0f0np0 (the "f0" pair),
  # P1 = enp1s0f1np1 + enP2p1s0f1np1 (the "f1" pair). One physical cable
  # therefore appears as two link entries (-0 = card1 rail, -1 = card2 rail).
  # Ring: each node's P0 goes to the next node's P1; the -0 rail lives in
  # 172.16.5–.11, the -1 rail in .6–.12.
  links = [
    # astrolabe P0 → octant P1
    {
      id = "astrolabe-octant-0";
      endpoints = {
        astrolabe = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:40:35:06";
          address = "172.16.5.54/24";
        };
        octant = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:be:70:fe";
          address = "172.16.5.57/24";
        };
      };
    }
    {
      id = "astrolabe-octant-1";
      endpoints = {
        astrolabe = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:40:35:0a";
          address = "172.16.6.54/24";
        };
        octant = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:be:71:02";
          address = "172.16.6.57/24";
        };
      };
    }
    # octant P0 → chronometer P1
    {
      id = "octant-chronometer-0";
      endpoints = {
        octant = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:be:70:fd";
          address = "172.16.7.57/24";
        };
        chronometer = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:40:fb:cf";
          address = "172.16.7.55/24";
        };
      };
    }
    {
      id = "octant-chronometer-1";
      endpoints = {
        octant = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:be:71:01";
          address = "172.16.8.57/24";
        };
        chronometer = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:40:fb:d3";
          address = "172.16.8.55/24";
        };
      };
    }
    # chronometer P0 → sextant P1
    {
      id = "chronometer-sextant-0";
      endpoints = {
        chronometer = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:40:fb:ce";
          address = "172.16.9.55/24";
        };
        sextant = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:40:c4:2f";
          address = "172.16.9.56/24";
        };
      };
    }
    {
      id = "chronometer-sextant-1";
      endpoints = {
        chronometer = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:40:fb:d2";
          address = "172.16.10.55/24";
        };
        sextant = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:40:c4:33";
          address = "172.16.10.56/24";
        };
      };
    }
    # sextant P0 → astrolabe P1 (ring wrap)
    {
      id = "sextant-astrolabe-0";
      endpoints = {
        sextant = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:40:c4:2e";
          address = "172.16.11.56/24";
        };
        astrolabe = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:40:35:07";
          address = "172.16.11.54/24";
        };
      };
    }
    {
      id = "sextant-astrolabe-1";
      endpoints = {
        sextant = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:40:c4:32";
          address = "172.16.12.56/24";
        };
        astrolabe = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:40:35:0b";
          address = "172.16.12.54/24";
        };
      };
    }
  ];

  addressWithoutPrefix = address: builtins.head (lib.splitString "/" address);

  # The /24 carrying `address`, as a route destination (e.g. 172.16.7.0/24).
  subnetPrefix =
    address:
    let
      parts = lib.splitString "." (addressWithoutPrefix address);
    in
    lib.concatStringsSep "." (lib.take 3 parts) + ".0/24";

  linksFor =
    nodeName:
    lib.concatMap (
      link:
      let
        endpointNames = builtins.attrNames link.endpoints;
        peerNames = builtins.filter (name: name != nodeName) endpointNames;
      in
      assert lib.assertMsg (
        builtins.length endpointNames == 2
      ) "DGX Spark RDMA link ${link.id} must have exactly two endpoints";
      if !builtins.hasAttr nodeName link.endpoints then
        [ ]
      else
        let
          local = link.endpoints.${nodeName};
          peerNode = builtins.head peerNames;
          peer = link.endpoints.${peerNode};
        in
        [
          {
            inherit (local) name mac address;
            inherit peerNode;
            linkId = link.id;
            peerAddress = addressWithoutPrefix peer.address;
            peerControlAddress = controlAddresses.${peerNode};
            peerMac = peer.mac;
            # Subnets reachable only THROUGH this peer (its other cable).
            # RoCE v2 is UDP-encapsulated and routable: with these static
            # routes + kernel forwarding, ANY node pair can serve a TP2 rank
            # pair without direct rails (routed hop, ~half the striped
            # bandwidth). See keel OQ-0055.
            farRoutes = lib.unique (
              builtins.map (l: subnetPrefix l.endpoints.${peerNode}.address) (
                builtins.filter (
                  l:
                  l.id != link.id
                  && builtins.hasAttr peerNode l.endpoints
                  && !builtins.hasAttr nodeName l.endpoints
                ) links
              )
            );
          }
        ]
    ) links;

  # Ring walking order: node[i]'s physical port P0 cables to node[i+1]'s P1,
  # and the last node's P0 wraps to node[0]'s P1. Matches the links list.
  #
  # This is also the PHYSICAL stack order (verified against the live cabling
  # 2026-11-17: all 8 rails ping green across the four edges, both
  # directions, with static-ARP MAC pinning — a rail only answers if the
  # physical cable connects the two ports owning its IPs/MACs). The
  # fabric.homelab.io/ring-position=<index> k3s labels (declared in the
  # dgx-spark module) let Conductor pick ring-adjacent pairs for TP2 lanes
  # (OQ-0055); labels were bootstrapped by hand on 2026-11-17 for the nodes
  # provisioned before the label commit and are re-asserted from here on any
  # rebuild. If a label ever disagrees with the cabling, the lane's fabric
  # preflight fails loudly ("expected two rails to peer, found 0") — fix the
  # label or the cable, never both blindly.
  ringOrder = [
    "astrolabe" # stack position 1 (top)
    "octant" # stack position 2
    "chronometer" # stack position 3
    "sextant" # stack position 4 (bottom)
  ];

  ringPositionFor =
    nodeName:
    if builtins.elem nodeName ringOrder then
      toString (lib.lists.findFirstIndex (n: n == nodeName) (-1) ringOrder)
    else
      throw "node ${nodeName} is not in the DGX Spark ring order";

  peerControlAddressesFor =
    nodeName: lib.unique (builtins.map (link: link.peerControlAddress) (linksFor nodeName));
in
assert lib.assertMsg (
  builtins.length (lib.unique (builtins.map (link: link.id) links)) == builtins.length links
) "DGX Spark RDMA link IDs must be unique";
{
  inherit
    controlAddresses
    links
    linksFor
    peerControlAddressesFor
    ringPositionFor
    ;
}
