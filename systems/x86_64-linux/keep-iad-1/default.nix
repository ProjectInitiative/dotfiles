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

    # Cluster networking is left to the fast private interconnect.
    networkType = "standard";

    # Provision first, enable after confirming the internal network layout.
    k8sEnable = false;

    # TODO after provisioning: e.g. "ens4"
    clusterInterface = "";
    # TODO after provisioning: the private IP and NIC for this node
    nodeIp = "";
    nodeIface = "";

    # No public ingress until hardening tests pass.
    publicIngress = false;

    # Infisical Agent placeholders. Populate the universal-auth credentials at
    # /var/lib/infisical/client-id and client-secret on the node, then set the
    # real project ID. The agent renders the tailscale/k3s/user secret files.
    infisical = {
      enable = true;
      projectId = "<INFISICAL_PROJECT_ID>";
      environment = "prod";
      credentialsDir = "/var/lib/infisical";
      # manageUserPassword = true;  # enable once the agent is delivering secrets
    };
  };
}
