# First server / control-plane node for the independent cloud cluster in OVH IAD.
#
# k3s is intentionally disabled here. The host, tailscale, firewall, and disko
# plumbing are provisioned first so the private interconnect can be inspected.
# Once you know the private NIC + IP scheme, set `clusterInterface`, `nodeIp`,
# and `nodeIface`, then flip `k8sEnable = true`.
{
  config,
  namespace,
  ...
}:
{
  ${namespace}.hosts.keep = {
    enable = true;

    role = "server";
    isFirstK8sNode = true;

    # Cluster networking is left to the fast private interconnect (OVH vRack).
    # "wireguard" = flannel wireguard-native: cluster comms stay encrypted even
    # though the vRack is private (DEC-0035). The role opens UDP 51871 on the
    # cluster interfaces for this.
    networkType = "wireguard";

    # Provision first, enable after confirming the internal network layout.
    k8sEnable = false;

    # TODO after provisioning: e.g. "ens4"
    clusterInterface = "";
    # TODO after provisioning: the private IP and NIC for this node
    nodeIp = "";
    nodeIface = "";

    # No public ingress until hardening tests pass.
    publicIngress = false;

    # Infisical Agent placeholders. Set the real project ID. Seed the
    # universal-auth credentials (/var/lib/infisical/client-id + client-secret)
    # AND the initial password hash (/var/lib/infisical-secrets/user_password)
    # at provision time via `nixos-anywhere --extra-files` (OQ-0021) — the
    # agent re-renders the tailscale/k3s/user secret files from then on.
    infisical = {
      enable = true;
      projectId = "<INFISICAL_PROJECT_ID>";
      environment = "prod";
      credentialsDir = "/var/lib/infisical";
      # Password sudo (DEC-0035): render USER_PASSWORD_HASH for wheelNeedsPassword.
      manageUserPassword = true;
    };
  };
}
