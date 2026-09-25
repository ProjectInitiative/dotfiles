{ lib }:
let
  # The switchless fabric is declared once. Each link has exactly two endpoints;
  # linksFor derives reciprocal peer identity, addresses, and MACs so those
  # values cannot drift between host configurations.
  links = [
    {
      id = "chronometer-sextant-0";
      endpoints = {
        chronometer = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:40:fb:cf";
          address = "172.16.5.55/24";
        };
        sextant = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:40:c4:2f";
          address = "172.16.5.56/24";
        };
      };
    }
    {
      id = "chronometer-sextant-1";
      endpoints = {
        chronometer = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:40:fb:d3";
          address = "172.16.6.55/24";
        };
        sextant = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:40:c4:33";
          address = "172.16.6.56/24";
        };
      };
    }
    {
      id = "chronometer-octant-0";
      endpoints = {
        chronometer = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:40:fb:ce";
          address = "172.16.7.55/24";
        };
        octant = {
          name = "enp1s0f1np1";
          mac = "30:c5:99:be:70:fe";
          address = "172.16.7.57/24";
        };
      };
    }
    {
      id = "chronometer-octant-1";
      endpoints = {
        chronometer = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:40:fb:d2";
          address = "172.16.8.55/24";
        };
        octant = {
          name = "enP2p1s0f1np1";
          mac = "30:c5:99:be:71:02";
          address = "172.16.8.57/24";
        };
      };
    }
    {
      id = "sextant-octant-0";
      endpoints = {
        sextant = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:40:c4:2e";
          address = "172.16.9.56/24";
        };
        octant = {
          name = "enp1s0f0np0";
          mac = "30:c5:99:be:70:fd";
          address = "172.16.9.57/24";
        };
      };
    }
    {
      id = "sextant-octant-1";
      endpoints = {
        sextant = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:40:c4:32";
          address = "172.16.10.56/24";
        };
        octant = {
          name = "enP2p1s0f0np0";
          mac = "30:c5:99:be:71:01";
          address = "172.16.10.57/24";
        };
      };
    }
  ];

  addressWithoutPrefix = address: builtins.head (lib.splitString "/" address);

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
            peerMac = peer.mac;
          }
        ]
    ) links;
in
assert lib.assertMsg (
  builtins.length (lib.unique (builtins.map (link: link.id) links)) == builtins.length links
) "DGX Spark RDMA link IDs must be unique";
{
  inherit links linksFor;
}
