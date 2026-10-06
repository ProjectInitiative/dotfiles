# Third server / control-plane node for the independent cloud cluster in OVH IAD.
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

    # "wireguard" = flannel wireguard-native: cluster comms stay encrypted even
    # though the OVH vRack is private (DEC-0035). UDP 51871 opened by the role.
    networkType = "wireguard";
    k8sEnable = false;

    # TODO after provisioning
    clusterInterface = "";
    nodeIp = "";
    nodeIface = "";

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
