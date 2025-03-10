{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.services.k8s;
in
{
  options.${namespace}.services.k8s = with types; {
    enable = mkBoolOpt false "Whether or not to enable Kubernetes cluster with k3s.";
    isFirstNode = mkBoolOpt false "Whether this node is the first node that initializes the cluster.";
    tokenFile =
      mkOpt str ""
        "File path containing k3s token to use when connecting to the server. This option only makes sense for an agent.";
    serverAddr =
      mkOpt str ""
        "Address of the server node to connect to (not needed for the first node).";
    role = mkOpt (enum [
      "server"
      "agent"
    ]) "agent" "Role of this node (server or agent).";
    # Network type - mutually exclusive options
    networkType = mkOpt (enum [
      "standard"
      "tailscale"
      "wireguard"
      "cilium"
    ]) "standard" "Network type to use for cluster communications.";

    # Cilium specific options
    cilium = {
      version = mkOpt str "1.17.1" "Cilium version to install.";
      podCIDR = mkOpt str "10.42.0.0/16" "Pod CIDR for Cilium IPAM.";
      installScript = mkOpt str "" "Custom install script for Cilium (leave empty for default script).";
    };

    gpuSupport = mkBoolOpt false "Enable GPU support for this node.";
    extraArgs = mkOpt (listOf str) [ ] "Additional arguments to pass to k3s.";
  };

  config = mkIf cfg.enable {
    # Input validation - ensure mutually exclusive
    assertions = [
      {
        assertion = cfg.networkType != "wireguard" || cfg.networkType != "tailscale";
        message = "Network types 'wireguard' and 'tailscale' are mutually exclusive.";
      }
    ];

    # NETWORKING
    # networking.firewall.allowedTCPPorts = [
    #   6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
    #   # 2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
    #   # 2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
    # ];
    # networking.firewall.allowedUDPPorts = [
    #   # 8472 # k3s, flannel: required if using multi-node for inter-node networking
    # ];

    # Create Cilium install script if using Cilium
    system.activationScripts = mkIf (cfg.networkType == "cilium") {
      install-cilium =
        let
          ciliumInstallScript =
            if cfg.cilium.installScript != "" then
              cfg.cilium.installScript
            else
              ''
                #!/bin/sh
                # Wait for k3s to be ready
                until kubectl get nodes &>/dev/null; do
                  echo "Waiting for k3s API to be available..."
                  sleep 5
                done

                # Install Cilium
                cilium install \
                  --version ${cfg.cilium.version} \
                  --set=ipam.operator.clusterPoolIPv4PodCIDRList="${cfg.cilium.podCIDR}"
                  --set=k8sServiceHost=127.0.0.1 \
                  --set=k8sServicePort=6443
              '';
        in
        stringAfter [ "users" "groups" ] ''
          # Create Cilium install script
          mkdir -p /var/lib/k3s/cilium
          cat > /var/lib/k3s/cilium/install.sh << 'EOF'
          ${ciliumInstallScript}
          EOF
          chmod +x /var/lib/k3s/cilium/install.sh

          # Create default CNI config directory and file for k3s
          mkdir -p /etc/cni/net.d
          cat > /etc/cni/net.d/10-cilium.conflist << 'EOF'
          {
            "name": "cilium",
            "cniVersion": "0.3.1",
            "plugins": [
              {
                "type": "cilium-cni"
              }
            ]
          }
          EOF
        '';
    };

    # Add systemd service to install Cilium after k3s starts (first node only)
    systemd.services.cilium-install = mkIf (cfg.networkType == "cilium" && cfg.isFirstNode) {
      description = "Install Cilium CNI";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      path = with pkgs; [
        cilium-cli
        kubectl
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/var/lib/k3s/cilium/install.sh";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    # Enable Wireguard kernel module if wireguard is selected
    boot.extraModulePackages = optionals (cfg.networkType == "wireguard") [
      config.boot.kernelPackages.wireguard
    ];
    boot.kernelModules = optionals (cfg.networkType == "wireguard") [ "wireguard" ];

    # Add GPU drivers if GPU support is enabled
    hardware.opengl.enable = mkIf cfg.gpuSupport true;
    hardware.nvidia.package = mkIf cfg.gpuSupport config.boot.kernelPackages.nvidiaPackages.stable;
    hardware.nvidia.modesetting.enable = mkIf cfg.gpuSupport true;

    ${namespace} = {
      # Enable Tailscale if needed
      networking.tailscale = mkIf (cfg.networkType == "tailscale") enabled;

      # use custom version, not provided in nixpkgs
      services.k3s = {
        enable = true;
        role = cfg.role;
        tokenFile = cfg.tokenFile;

        # Configure based on whether this is the first node
        clusterInit = cfg.isFirstNode;
        serverAddr = mkIf (!cfg.isFirstNode) cfg.serverAddr;

        # Combine auto-generated flags with user-provided extra flags
        extraFlags =
          let
            # Add GPU support if needed
            gpuFlags = (
              optionals cfg.gpuSupport [
                "--kubelet-arg=feature-gates=DevicePlugins=true"
                "--kubelet-arg=allow-privileged=true"
              ]
            );
            # Network-specific flags
            networkFlags =
              if cfg.networkType == "tailscale" then
                [
                  "--flannel-iface=tailscale0"
                  "--flannel-external-ip"
                  "--node-ip=$(${pkgs.tailscale}/bin/tailscale ip -4)"
                  "--node-external-ip=$(${pkgs.tailscale}/bin/tailscale ip -4)"
                  "--flannel-backend=vxlan"
                ]
              else if cfg.networkType == "wireguard" then
                [
                  "--flannel-backend=wireguard-native"
                ]
              else if cfg.networkType == "cilium" then
                [
                  "--flannel-backend=none"
                  "--disable-network-policy"
                  "--disable=traefik"
                  "--disable=servicelb" 
                  # We need to use dummy CNI at first start to avoid hanging
                  "--cni-bin-dir=/var/lib/rancher/k3s/data/current/bin"
                  # Still telling k3s that we'll replace the CNI soon with cilium
                  "--kubelet-arg=network-plugin=cni"
                ]
              else
                [ ]; # Standard networking doesn't need special flags
          in
          networkFlags ++ gpuFlags ++ cfg.extraArgs;
      };
    };

    # For Cilium: create a basic "bridge" CNI config to bootstrap k3s without hanging
    # This is needed because k3s expects a CNI plugin to be available at startup
    # Later, cilium-install service will replace this with the actual Cilium CNI
    systemd.services.k3s = mkIf (cfg.networkType == "cilium") {
      preStart = ''
        mkdir -p /var/lib/rancher/k3s/data/current/bin
        ${pkgs.cni-plugins}/bin/bridge --version || true
        mkdir -p /var/lib/rancher/k3s/agent/etc/cni/net.d
        cp ${pkgs.cni-plugins}/bin/* /var/lib/rancher/k3s/data/current/bin/
        
        # Create a simple bridge CNI config for initial bootstrap
        cat > /var/lib/rancher/k3s/agent/etc/cni/net.d/10-bridge.conflist << EOF
        {
          "cniVersion": "0.3.1",
          "name": "bridge",
          "plugins": [
            {
              "type": "bridge",
              "bridge": "cni0",
              "isGateway": true,
              "ipMasq": true,
              "ipam": {
                "type": "host-local",
                "ranges": [
                  [{"subnet": "${cfg.cilium.podCIDR}"}]
                ],
                "routes": [{"dst": "0.0.0.0/0"}]
              }
            },
            {
              "type": "portmap",
              "capabilities": {"portMappings": true}
            }
          ]
        }
        EOF
      '';
    };

    
  };
}
