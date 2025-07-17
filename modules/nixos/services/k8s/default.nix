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
    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      description = "File path containing k3s token to use when connecting to the server.";
      default = null;
    };
    serverAddr =
      mkOpt str ""
        "Address of the server node to connect to (not needed for the first node).";
    nodeIp = mkOpt str "" "Use different node IP rather than default interface.";
    nodeIface = mkOpt str "" "Use different node iface rather than default interface.";
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

    # kubectl -n kube-system edit secrets/k3s-serving
    # kube-vip specific options
    kubeVip = {
      enable = mkBoolOpt false "Whether to enable kube-vip for high availability.";
      version = mkOpt str "v0.5.12" "kube-vip version to install.";
      vip = mkOpt str "192.168.0.40" "Virtual IP address for kube-vip.";
      interface = mkOpt str "eth0" "Network interface for kube-vip to use.";
      mode = mkOpt (enum [
        "arp"
        "bgp"
        "layer2"
      ]) "arp" "Mode for kube-vip to operate in.";
      controlPlane = mkBoolOpt true "Whether to use kube-vip for control plane HA.";
      services = mkBoolOpt true "Whether to use kube-vip for service load balancing.";
      leaderElection = mkBoolOpt true "Whether to use leader election for kube-vip.";
    };

    gpuSupport = mkBoolOpt false "Enable GPU support for this node.";
    extraArgs = mkOpt (listOf str) [ ] "Additional arguments to pass to k3s.";
    environmentFile = mkOpt (nullOr path) null "Environment file for k3s service.";

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
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking = {
      firewall = {
        enable = false;
        allowPing = true;
        # extraCommands = ''
        #   # Log all dropped packets
        #   iptables -A INPUT -j LOG --log-prefix "FIREWALL_DROP_INPUT: "
        #   iptables -A FORWARD -j LOG --log-prefix "FIREWALL_DROP_FORWARD: "
        #   iptables -A OUTPUT -j LOG --log-prefix "FIREWALL_DROP_OUTPUT: "
        # '';
        allowedTCPPorts =
          [
            53 # k8s DNS access
            80 # http
            443 # https
            8080 # reserved http
            6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
            2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
            2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
            9153 # backup k8s dns

            # 10250 # k3s metrics port
          ]
          ++ lib.optionals (cfg.networkType == "cilium") [
            4240 # cluster health checks (cilium-health)
            4244 # Hubble server
            4245 # Hubble Relay
            4250 # Mutual Authentication port
            4251 # Spire Agent health check port (listening on 127.0.0.1 or ::1)
            6060 # cilium-agent pprof server (listening on 127.0.0.1)
            6061 # cilium-operator pprof server (listening on 127.0.0.1)
            6062 # Hubble Relay pprof server (listening on 127.0.0.1)
            9878 # cilium-envoy health listener (listening on 127.0.0.1)
            9879 # cilium-agent health status API (listening on 127.0.0.1 and/or ::1)
            9890 # cilium-agent gops server (listening on 127.0.0.1)
            9891 # operator gops server (listening on 127.0.0.1)
            9893 # Hubble Relay gops server (listening on 127.0.0.1)
            9901 # cilium-envoy Admin API (listening on 127.0.0.1)
            9962 # cilium-agent Prometheus metrics
            9963 # cilium-operator Prometheus metrics
            9964 # cilium envoy
          ];
        allowedTCPPortRanges = [
          {
            from = 10250;
            to = 10252;
          } # Kubelet and other k8s components
          {
            from = 30000;
            to = 32767;
          } # NodePort range
        ];
        allowedUDPPorts =
          [
            53 # k8s DNS access
            8472 # k3s VXLAN overlay: required if using multi-node for inter-node networking
          ]
          ++ lib.optionals (cfg.networkType == "cilium") [
            51871 # WireGuard encryption tunnel endpoint
          ];

      };
    };

    environment.systemPackages = mkIf (cfg.networkType == "cilium") [
      pkgs.cilium-cli
      pkgs.procps
      pkgs.cni-plugins
    ];

    # Add systemd service to install Cilium after k3s starts (first node only)
    systemd.services.cilium-install = mkIf (cfg.networkType == "cilium" && cfg.isFirstNode) {
      description = "Install Cilium CNI";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      path = with pkgs; [
        cilium-cli
        procps
        cni-plugins
        k3s
        # kubectl
      ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "30s";
        # Set a home directory for the service
        Environment = [
          "HOME=/root"
          "XDG_CACHE_HOME=/root/.cache"
          "KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        ];
      };
      script = ''

        # Wait for k3s to be ready
        until kubectl get nodes &>/dev/null; do
          echo "Waiting for k3s API to be available..."
          sleep 5
        done

        # Check if Cilium is already installed
        if kubectl get daemonset cilium -n kube-system &>/dev/null; then
          echo "Cilium is already installed, checking status..."
          cilium status
          # Optionally update configurations if needed
          # kubectl set ...
          exit 0
        fi

        # Install Cilium if not already installed
        echo "Installing Cilium..."
        cilium install \
          --version ${cfg.cilium.version} \
          --set=ipam.operator.clusterPoolIPv4PodCIDRList="${cfg.cilium.podCIDR}"
          # --set=k8sServiceHost=127.0.0.1 \
          # --set=k8sServicePort=6443

        # Verify installation
        echo "Verifying Cilium installation..."
        cilium status

      '';
    };

    # Add systemd service to install kube-vip after k3s starts (first node only)
    systemd.services.kube-vip-install = mkIf (cfg.kubeVip.enable && cfg.isFirstNode) {
      description = "Install kube-vip for high availability";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      path = with pkgs; [
        kubectl
        curl
        coreutils
        k3s
      ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "30s";
        Environment = [
          "HOME=/root"
          "XDG_CACHE_HOME=/root/.cache"
          "KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        ];
      };
      script =
        let
          kubevipFlags =
            [
              "--interface ${cfg.kubeVip.interface}"
              "--address ${cfg.kubeVip.vip}"
              "--inCluster"
              "--taint"
            ]
            ++ optionals cfg.kubeVip.controlPlane [ "--controlplane" ]
            ++ optionals cfg.kubeVip.services [ "--services" ]
            ++ optionals (cfg.kubeVip.mode == "arp") [ "--arp" ]
            ++ optionals (cfg.kubeVip.mode == "bgp") [ "--bgp" ]
            ++ optionals (cfg.kubeVip.mode == "layer2") [ "--layer2" ]
            ++ optionals cfg.kubeVip.leaderElection [ "--leaderElection" ];

          # Join the flags with spaces for the manifest command
          kubevipFlagsStr = concatStringsSep " " kubevipFlags;
        in
        ''
          kubectl get nodes
          # Wait for k3s to be ready
          until kubectl get nodes &>/dev/null; do
            echo "Waiting for k3s API to be available..."
            sleep 5
          done

          # Check if kube-vip is already installed
          if kubectl get daemonset kube-vip-ds -n kube-system &>/dev/null; then
            echo "kube-vip is already installed"
            exit 0
          fi

          # Create manifests directory if it doesn't exist
          mkdir -p /var/lib/rancher/k3s/server/manifests/

          # Apply RBAC for kube-vip
          echo "Installing kube-vip RBAC..."
          curl -s https://kube-vip.io/manifests/rbac.yaml > /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml

          # Generate kube-vip manifest
          echo "Generating kube-vip manifest..."

          # Create temporary alias for kube-vip container
          KVVERSION="${cfg.kubeVip.version}"

          # Create the manifest using container runtime
          if command -v docker &> /dev/null; then
            echo "Using Docker to generate manifest..."
            MANIFEST=$(docker run --network host --rm ghcr.io/kube-vip/kube-vip:$KVVERSION manifest daemonset ${kubevipFlagsStr})
          elif command -v ctr &> /dev/null; then
            echo "Using containerd to generate manifest..."
            ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
            MANIFEST=$(ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest daemonset ${kubevipFlagsStr})
          elif command -v nerdctl &> /dev/null; then
            echo "Using nerdctl to generate manifest..."
            MANIFEST=$(nerdctl run --network host --rm ghcr.io/kube-vip/kube-vip:$KVVERSION manifest daemonset ${kubevipFlagsStr})
          else
            echo "No container runtime found, cannot generate kube-vip manifest"
            exit 1
          fi

          # Save the manifest to the auto-deploy directory
          echo "$MANIFEST" > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml

          echo "kube-vip installation completed!"
        '';
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

    # nixpkgs services
    services = {
    };

    ${namespace} = {
      # Enable Tailscale if needed
      networking.tailscale = mkIf (cfg.networkType == "tailscale") enabled;

      services = {
        # use custom version, not provided in nixpkgs
        k3s = {
          enable = true;
          role = cfg.role;
          tokenFile = cfg.tokenFile;
          environmentFile = cfg.environmentFile;

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
              node-ip =
                if cfg.nodeIp != "" then
                  [
                    "--node-ip=${cfg.nodeIp}"
                    # "--node-external-ip=${cfg.nodeIp}"
                  ]
                else
                  [ ];
              node-iface =
                if cfg.nodeIface != "" then
                  [
                    "--flannel-iface=${cfg.nodeIface}"
                  ]
                else
                  [ ];

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
                  ++ node-ip
                  ++ node-iface
                else if cfg.networkType == "cilium" then
                  [
                    "--flannel-backend=none"
                    "--disable-network-policy"
                    "--disable=traefik"
                    "--disable=servicelb"
                    # # We need to use dummy CNI at first start to avoid hanging
                    # "--cni-bin-dir=/var/lib/rancher/k3s/data/current/bin"
                    # # Still telling k3s that we'll replace the CNI soon with cilium
                    # "--kubelet-arg=network-plugin=cni"
                  ]
                  ++ node-ip
                else
                  [ ] ++ node-ip ++ node-iface; # Standard networking doesn't need special flags
            in
            networkFlags ++ gpuFlags ++ cfg.extraArgs;
        };
      };

    };

    # Create CNI config directory with all needed configurations
    # systemd.tmpfiles.rules = mkIf (cfg.networkType == "cilium") [
    #   "d /opt/cni/bin 0755 root root - -"
    #   "L+ /opt/cni/bin/bridge ${pkgs.cni-plugins}/bin/bridge - - - -"
    #   "L+ /opt/cni/bin/loopback ${pkgs.cni-plugins}/bin/loopback - - - -"
    #   "L+ /opt/cni/bin/host-local ${pkgs.cni-plugins}/bin/host-local - - - -"
    #   "L+ /opt/cni/bin/portmap ${pkgs.cni-plugins}/bin/portmap - - - -"
    #   "d /etc/cni/net.d 0755 root root - -"
    #   "d /run/flannel 0755 root root - -"
    # ];

    # For Cilium: create a basic "bridge" CNI config to bootstrap k3s without hanging
    # This is needed because k3s expects a CNI plugin to be available at startup
    # Later, cilium-install service will replace this with the actual Cilium CNI

  };
}
