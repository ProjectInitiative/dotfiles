# Second server / control-plane node for the independent cloud cluster in OVH IAD.
#
# k3s is intentionally disabled here. See keep-iad-1 for the provisioning order:
# confirm the private interconnect first, then fill in the TODOs and enable k3s.
{
  config,
  namespace,
  ...
}:
{
  ${namespace}.hosts.keep = {
    enable = true;

    role = "server";
    isFirstK8sNode = false;

    # TODO: set to the head of the private interconnect (or tailnet) once known.
    k8sServerAddr = "";

    networkType = "standard";
    k8sEnable = false;

    # TODO after provisioning
    clusterInterface = "";
    nodeIp = "";
    nodeIface = "";

    publicIngress = false;

    # Infisical Agent placeholders. Populate the universal-auth credentials at
    # /var/lib/infisical/client-id and client-secret, then set the real project
    # ID. As a joiner, the agent renders the K3S_TOKEN the node needs.
    infisical = {
      enable = true;
      projectId = "<INFISICAL_PROJECT_ID>";
      environment = "prod";
      credentialsDir = "/var/lib/infisical";
      # manageUserPassword = true;  # enable once the agent is delivering secrets
    };
  };
}
