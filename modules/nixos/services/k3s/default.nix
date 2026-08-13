{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
let
  cfg = config.${namespace}.services.k3s;

  removeOption =
    config: instruction:
    lib.mkRemovedOptionModule (
      [
        "services"
        "k3s"
      ]
      ++ config
    ) instruction;

  manifestDir = "${cfg.dataDir}/server/manifests";
  chartDir = "${cfg.dataDir}/server/static/charts";
  imageDir = "${cfg.dataDir}/agent/images";
  containerdConfigTemplateFile = "${cfg.dataDir}/agent/etc/containerd/config.toml.tmpl";

  manifestModule =
    let
      mkTarget =
        name:
        if lib.hasSuffix ".yaml" name || lib.hasSuffix ".yml" name then
          name
        else
          name + ".yaml";
    in
    lib.types.submodule (
      {
        name,
        config,
        options,
        ...
      }:
      {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this manifest file should be generated.";
          };

          target = lib.mkOption {
            type = lib.types.nonEmptyStr;
            example = lib.literalExpression "manifest.yaml";
            description = ''
              Name of the symlink relative to {file}`${manifestDir}`.
              Defaults to the attribute name.
            '';
          };

          content = lib.mkOption {
            type = with lib.types; nullOr (either attrs (listOf attrs));
            default = null;
            description = ''
              Content of the manifest file.

              A single attribute set generates a single-document YAML file.
              A list of attribute sets generates multiple YAML documents
              separated by `---` in a single file.
            '';
          };

          source = lib.mkOption {
            type = lib.types.path;
            example = lib.literalExpression "./manifests/app.yaml";
            description = "Path of the source YAML file.";
          };
        };

        config = {
          target = lib.mkDefault (mkTarget name);

          source = lib.mkIf (config.content != null) (
            let
              name' = "k3s-manifest-${builtins.baseNameOf name}";
              docName = "k3s-manifest-doc-${builtins.baseNameOf name}";
              yamlDocSeparator = builtins.toFile "yaml-doc-separator" "\n---\n";

              mkYaml =
                yamlName: value:
                (pkgs.formats.yaml { }).generate yamlName value;

              mkSource =
                value:
                if builtins.isList value then
                  pkgs.concatText name' (
                    lib.concatMap (
                      document:
                      [
                        yamlDocSeparator
                        (mkYaml docName document)
                      ]
                    ) value
                  )
                else
                  mkYaml name' value;
            in
            lib.mkDerivedConfig options.content mkSource
          );
        };
      }
    );

  enabledManifests =
    lib.filter
      (manifest: manifest.enable)
      (lib.attrValues cfg.manifests);

  linkManifestEntry =
    manifest:
    "${pkgs.coreutils-full}/bin/ln -sfn ${manifest.source} ${manifestDir}/${manifest.target}";

  linkImageEntry =
    image:
    "${pkgs.coreutils-full}/bin/ln -sfn ${image} ${imageDir}/${image.name}";

  linkChartEntry =
    let
      mkTarget =
        name:
        if lib.hasSuffix ".tgz" name then
          name
        else
          name + ".tgz";
    in
    name: value:
    "${pkgs.coreutils-full}/bin/ln -sfn ${value} ${chartDir}/${mkTarget (builtins.baseNameOf name)}";

  activateK3sContent = pkgs.writeShellScript "activate-k3s-content" ''
    set -euo pipefail

    ${lib.optionalString (
      builtins.length enabledManifests > 0
    ) "${pkgs.coreutils-full}/bin/mkdir -p ${manifestDir}"}

    ${lib.optionalString (
      cfg.charts != { }
    ) "${pkgs.coreutils-full}/bin/mkdir -p ${chartDir}"}

    ${lib.optionalString (
      builtins.length cfg.images > 0
    ) "${pkgs.coreutils-full}/bin/mkdir -p ${imageDir}"}

    ${builtins.concatStringsSep "\n" (
      map linkManifestEntry enabledManifests
    )}

    ${builtins.concatStringsSep "\n" (
      lib.mapAttrsToList linkChartEntry cfg.charts
    )}

    ${builtins.concatStringsSep "\n" (
      map linkImageEntry cfg.images
    )}

    ${lib.optionalString (cfg.containerdConfigTemplate != null) ''
      ${pkgs.coreutils-full}/bin/mkdir -p \
        "$(${pkgs.coreutils-full}/bin/dirname ${lib.escapeShellArg containerdConfigTemplateFile})"

      ${pkgs.coreutils-full}/bin/ln -sfn \
        ${
          pkgs.writeText
            "config.toml.tmpl"
            cfg.containerdConfigTemplate
        } \
        ${lib.escapeShellArg containerdConfigTemplateFile}
    ''}
  '';

  normalizedExtraFlags =
    if builtins.isList cfg.extraFlags then
      cfg.extraFlags
    else
      [ cfg.extraFlags ];

  startK3sScript =
    let
      kubeletParams =
        (lib.optionalAttrs cfg.gracefulNodeShutdown.enable {
          inherit (cfg.gracefulNodeShutdown)
            shutdownGracePeriod
            shutdownGracePeriodCriticalPods
            ;
        })
        // cfg.extraKubeletConfig;

      kubeletConfig =
        (pkgs.formats.yaml { }).generate "k3s-kubelet-config" (
          {
            apiVersion = "kubelet.config.k8s.io/v1beta1";
            kind = "KubeletConfiguration";
          }
          // kubeletParams
        );

      kubeProxyConfig =
        (pkgs.formats.yaml { }).generate "k3s-kubeProxy-config" (
          {
            apiVersion = "kubeproxy.config.k8s.io/v1alpha1";
            kind = "KubeProxyConfiguration";
          }
          // cfg.extraKubeProxyConfig
        );

      k3sCommand =
        lib.concatStringsSep " \\\n  " (
          [ "${cfg.package}/bin/k3s ${cfg.role}" ]
          ++ lib.optional cfg.clusterInit "--cluster-init"
          ++ lib.optional cfg.disableAgent "--disable-agent"
          ++ lib.optional (
            cfg.serverAddr != ""
          ) "--server ${lib.escapeShellArg cfg.serverAddr}"
          ++ lib.optional (
            cfg.token != ""
          ) "--token ${lib.escapeShellArg cfg.token}"
          ++ lib.optional (
            cfg.tokenFile != null
          ) "--token-file ${lib.escapeShellArg (toString cfg.tokenFile)}"
          ++ lib.optional (
            cfg.configPath != null
          ) "--config ${lib.escapeShellArg (toString cfg.configPath)}"
          ++ lib.optional (
            cfg.dataDir != "/var/lib/rancher/k3s"
          ) "--data-dir ${lib.escapeShellArg (toString cfg.dataDir)}"
          ++ lib.optional (
            kubeletParams != { }
          ) "--kubelet-arg=config=${lib.escapeShellArg (toString kubeletConfig)}"
          ++ lib.optional (
            cfg.extraKubeProxyConfig != { }
          ) "--kube-proxy-arg=config=${lib.escapeShellArg (toString kubeProxyConfig)}"
          ++ normalizedExtraFlags
        );
    in
    pkgs.writeShellScript "start-k3s" ''
      set -euo pipefail
      exec ${k3sCommand}
    '';

  /*
    Embedded-etcd administration wrapper.

    This command must generally be run through sudo because the K3s-managed
    etcd client certificates are not readable by unprivileged users.

    Examples:

      sudo k3s-etcdctl member list --write-out=table
      sudo k3s-etcdctl endpoint health --cluster
      sudo k3s-etcdctl endpoint status --cluster --write-out=table
  */
  k3sEtcdctl = pkgs.writeShellApplication {
    name = "k3s-etcdctl";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.etcd
    ];

    text = ''
      set -euo pipefail

      export ETCDCTL_API=3

      data_dir=${lib.escapeShellArg (toString cfg.dataDir)}
      etcd_tls_dir="$data_dir/server/tls/etcd"

      ca="$etcd_tls_dir/server-ca.crt"

      if [[ -r "$etcd_tls_dir/client.crt" ]] &&
         [[ -r "$etcd_tls_dir/client.key" ]]; then
        cert="$etcd_tls_dir/client.crt"
        key="$etcd_tls_dir/client.key"
      elif [[ -r "$etcd_tls_dir/server-client.crt" ]] &&
           [[ -r "$etcd_tls_dir/server-client.key" ]]; then
        cert="$etcd_tls_dir/server-client.crt"
        key="$etcd_tls_dir/server-client.key"
      else
        echo "k3s-etcdctl: unable to find an etcd client certificate." >&2
        echo >&2
        echo "Checked:" >&2
        echo "  $etcd_tls_dir/client.crt" >&2
        echo "  $etcd_tls_dir/client.key" >&2
        echo "  $etcd_tls_dir/server-client.crt" >&2
        echo "  $etcd_tls_dir/server-client.key" >&2
        echo >&2
        echo "This command is intended for a K3s server using embedded etcd." >&2
        exit 1
      fi

      if [[ ! -r "$ca" ]]; then
        echo "k3s-etcdctl: cannot read the etcd server CA:" >&2
        echo "  $ca" >&2
        echo >&2
        echo "Run this command as root:" >&2
        echo "  sudo k3s-etcdctl ..." >&2
        exit 1
      fi

      exec etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert="$ca" \
        --cert="$cert" \
        --key="$key" \
        "$@"
    '';
  };

  k3sEtcdHealth = pkgs.writeShellApplication {
    name = "k3s-etcd-health";

    runtimeInputs = [
      k3sEtcdctl
    ];

    text = ''
      set -euo pipefail

      exec k3s-etcdctl \
        endpoint health \
        --cluster \
        "$@"
    '';
  };

  k3sEtcdStatus = pkgs.writeShellApplication {
    name = "k3s-etcd-status";

    runtimeInputs = [
      k3sEtcdctl
    ];

    text = ''
      set -euo pipefail

      exec k3s-etcdctl \
        endpoint status \
        --cluster \
        --write-out=table \
        "$@"
    '';
  };

  k3sEtcdMembers = pkgs.writeShellApplication {
    name = "k3s-etcd-members";

    runtimeInputs = [
      k3sEtcdctl
    ];

    text = ''
      set -euo pipefail

      exec k3s-etcdctl \
        member list \
        --write-out=table \
        "$@"
    '';
  };

  /*
    Intended as a maintenance gate before restarting or rebooting another
    control-plane node.

    It exits nonzero if endpoint health fails.
  */
  k3sEtcdRequireHealthy = pkgs.writeShellApplication {
    name = "k3s-etcd-require-healthy";

    runtimeInputs = [
      k3sEtcdctl
    ];

    text = ''
      set -euo pipefail

      echo "Embedded-etcd members:"
      echo

      k3s-etcdctl \
        member list \
        --write-out=table

      echo
      echo "Embedded-etcd endpoint status:"
      echo

      k3s-etcdctl \
        endpoint status \
        --cluster \
        --write-out=table

      echo
      echo "Embedded-etcd health:"
      echo

      k3s-etcdctl \
        endpoint health \
        --cluster

      echo
      echo "Embedded-etcd cluster is healthy."
    '';
  };
in
{
  options.${namespace}.services.k3s = {
    enable = lib.mkEnableOption "k3s";

    package = lib.mkPackageOption pkgs "k3s" { };

    role = lib.mkOption {
      description = ''
        Whether K3s should run as a server or agent.

        When configured as a server:

        - It also runs workloads as an agent by default.
        - It starts as a standalone server using embedded SQLite by default.
        - Set `clusterInit = true` on the first server to initialize an
          embedded-etcd HA cluster.
        - Set `serverAddr` on additional servers to join the initialized
          HA cluster.

        When configured as an agent:

        - `serverAddr` is required unless supplied through `configPath`.
      '';

      default = "server";

      type = lib.types.enum [
        "server"
        "agent"
      ];
    };

    serverAddr = lib.mkOption {
      type = lib.types.str;

      description = ''
        The K3s server URL to connect to.

        Servers and agents must be able to communicate with the configured
        address. Review the K3s networking requirements when configuring
        firewalls and routing.
      '';

      example = "https://10.0.0.10:6443";
      default = "";
    };

    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;

      description = ''
        Initialize an HA cluster using embedded etcd.

        Set this on the first server that initializes the embedded-etcd
        cluster. Additional server nodes should leave this disabled and join
        through `serverAddr`.

        If an HA cluster using embedded etcd is already initialized, this
        option normally has no additional effect. It should nevertheless not
        be configured on joining servers.
      '';
    };

    token = lib.mkOption {
      type = lib.types.str;

      description = ''
        The K3s token used when connecting to a server.

        WARNING: This option stores the token in the world-readable Nix store.
        Prefer `tokenFile` for secrets.
      '';

      default = "";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;

      description = ''
        File containing the K3s token used when connecting to a server.

        The file should be provisioned outside the Nix store, for example by
        sops-nix or agenix.
      '';

      default = null;
    };

    extraFlags = lib.mkOption {
      description = "Additional flags passed to the K3s command.";

      type =
        with lib.types;
        either str (listOf str);

      default = [ ];

      example = [
        "--disable=traefik"
        "--cluster-cidr=10.24.0.0/16"
      ];
    };

    disableAgent = lib.mkOption {
      type = lib.types.bool;
      default = false;

      description = ''
        Disable the K3s agent components on a server.

        This option only applies when `role = "server"`.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;

      description = ''
        File containing environment variables for the K3s service in systemd
        EnvironmentFile format. See {manpage}`systemd.exec(5)`.
      '';

      default = null;
    };

    configPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;

      description = ''
        Path to a K3s YAML configuration file.

        This is useful when the configuration is generated at boot or
        provisioned outside the Nix store.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/rancher/k3s";
      description = "Directory used for K3s persistent data.";
    };

    manifests = lib.mkOption {
      type = lib.types.attrsOf manifestModule;
      default = { };

      example = lib.literalExpression ''
        deployment.source = ../manifests/deployment.yaml;

        my-service = {
          enable = false;
          target = "app-service.yaml";

          content = {
            apiVersion = "v1";
            kind = "Service";

            metadata = {
              name = "app-service";
            };

            spec = {
              selector = {
                "app.kubernetes.io/name" = "MyApp";
              };

              ports = [
                {
                  name = "name-of-service-port";
                  protocol = "TCP";
                  port = 80;
                  targetPort = "http-web-svc";
                }
              ];
            };
          };
        };

        nginx.content = [
          {
            apiVersion = "v1";
            kind = "Pod";

            metadata = {
              name = "nginx";

              labels = {
                "app.kubernetes.io/name" = "MyApp";
              };
            };

            spec = {
              containers = [
                {
                  name = "nginx";
                  image = "nginx:1.14.2";

                  ports = [
                    {
                      containerPort = 80;
                      name = "http-web-svc";
                    }
                  ];
                }
              ];
            };
          }

          {
            apiVersion = "v1";
            kind = "Service";

            metadata = {
              name = "nginx-service";
            };

            spec = {
              selector = {
                "app.kubernetes.io/name" = "MyApp";
              };

              ports = [
                {
                  name = "name-of-service-port";
                  protocol = "TCP";
                  port = 80;
                  targetPort = "http-web-svc";
                }
              ];
            };
          }
        ];
      '';

      description = ''
        Auto-deploying manifests linked into {file}`${manifestDir}` before K3s
        starts.

        Removing a manifest file does not automatically remove the resources
        it created. Use K3s AddOn disable mechanisms or `.skip` files when
        disabling packaged or managed AddOns.

        This option only applies to server nodes.
      '';
    };

    charts = lib.mkOption {
      type =
        with lib.types;
        attrsOf (either path package);

      default = { };

      example = lib.literalExpression ''
        nginx = ../charts/my-nginx-chart.tgz;
        redis = ../charts/my-redis-chart.tgz;
      '';

      description = ''
        Packaged Helm charts linked into {file}`${chartDir}` before K3s starts.

        The attribute name is used as the link target. A `.tgz` suffix is added
        when it is not already present.

        These charts are only made available to the K3s Helm controller; they
        are not deployed automatically by this option.

        This option only applies to server nodes.
      '';
    };

    containerdConfigTemplate = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;

      example = lib.literalExpression ''
        # Base K3s config
        {{ template "base" . }}

        # Add a custom runtime
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."custom"]
          runtime_type = "io.containerd.runc.v2"

        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."custom".options]
          BinaryName = "/path/to/custom-container-runtime"
      '';

      description = ''
        Containerd configuration template placed at:

        `${containerdConfigTemplateFile}`

        See the K3s documentation for configuring containerd.
      '';
    };

    images = lib.mkOption {
      type =
        with lib.types;
        listOf package;

      default = [ ];

      example = lib.literalExpression ''
        [
          (pkgs.dockerTools.pullImage {
            imageName = "docker.io/bitnami/keycloak";
            imageDigest = "sha256:714dfadc66a8e3adea6609bda350345bd3711657b7ef3cf2e8015b526bac2d6b";
            hash = "sha256-IM2BLZ0EdKIZcRWOtuFY9TogZJXCpKtPZnMnPsGlq0Y=";
            finalImageTag = "21.1.2-debian-11-r0";
          })

          config.services.k3s.package.airgapImages
        ]
      '';

      description = ''
        Derivations providing container images.

        Images are linked into {file}`${imageDir}` and imported by the K3s
        agent. Consider including the matching K3s air-gap image archive when
        pre-provisioning nodes without registry access.

        This option only applies to nodes with an enabled agent.
      '';
    };

    gracefulNodeShutdown = {
      enable = lib.mkEnableOption ''
        graceful Kubernetes node shutdown handling
      '';

      shutdownGracePeriod = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "30s";
        example = "1m30s";

        description = ''
          Total amount of time allocated for pod termination during system
          shutdown.
        '';
      };

      shutdownGracePeriodCriticalPods = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "10s";
        example = "15s";

        description = ''
          Portion of the shutdown grace period reserved for terminating
          critical pods.

          This value should be shorter than `shutdownGracePeriod`.
        '';
      };
    };

    extraKubeletConfig = lib.mkOption {
      type =
        with lib.types;
        attrsOf anything;

      default = { };

      example = {
        podsPerCore = 3;
        memoryThrottlingFactor = 0.69;
        containerLogMaxSize = "5Mi";
      };

      description = ''
        Additional values added to the generated KubeletConfiguration file.

        Only settings supported by the Kubernetes KubeletConfiguration API may
        be supplied here.
      '';
    };

    extraKubeProxyConfig = lib.mkOption {
      type =
        with lib.types;
        attrsOf anything;

      default = { };

      example = {
        mode = "nftables";

        clientConnection.kubeconfig =
          "/var/lib/rancher/k3s/agent/kubeproxy.kubeconfig";
      };

      description = ''
        Additional values added to the generated KubeProxyConfiguration file.

        K3s overrides the kubeconfig argument, so set
        `clientConnection.kubeconfig` when using this option.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    warnings =
      lib.optional (
        cfg.role != "server" && cfg.manifests != { }
      ) ''
        k3s: Auto-deploying manifests are only installed on server nodes
        (`role = "server"`). They will be ignored by this node.
      ''
      ++ lib.optional (
        cfg.role != "server" && cfg.charts != { }
      ) ''
        k3s: Helm charts are only made available on server nodes
        (`role = "server"`). They will be ignored by this node.
      ''
      ++ lib.optional (
        cfg.disableAgent && cfg.images != [ ]
      ) ''
        k3s: Images are only imported on nodes with an enabled agent.
        They will be ignored by this node.
      ''
      ++ lib.optional (
        cfg.role == "agent"
        && cfg.configPath == null
        && cfg.serverAddr == ""
      ) ''
        k3s: An agent should set `serverAddr` or provide a `server` key through
        `configPath`.
      ''
      ++ lib.optional (
        cfg.role == "agent"
        && cfg.configPath == null
        && cfg.tokenFile == null
        && cfg.token == ""
      ) ''
        k3s: An agent should set `token`, `tokenFile`, or provide a token
        through `configPath`.
      '';

    assertions = [
      {
        assertion =
          cfg.role != "agent"
          || !cfg.disableAgent;

        message = ''
          k3s: `disableAgent` must be false when `role = "agent"`.
        '';
      }

      {
        assertion =
          cfg.role != "agent"
          || !cfg.clusterInit;

        message = ''
          k3s: `clusterInit` must be false when `role = "agent"`.
        '';
      }

      {
        assertion =
          !(
            cfg.role == "server"
            && cfg.clusterInit
            && cfg.serverAddr != ""
          );

        message = ''
          k3s: `clusterInit` and `serverAddr` must not both be set.

          Use `clusterInit` only on the initial server. Joining servers should
          use `serverAddr`.
        '';
      }

      {
        assertion =
          !(cfg.token != "" && cfg.tokenFile != null);

        message = ''
          k3s: Configure either `token` or `tokenFile`, not both.
        '';
      }

      {
        assertion =
          !(cfg.configPath != null && cfg.clusterInit);

        message = ''
          k3s: `clusterInit` should not be set alongside `configPath`.

          Put the cluster initialization setting in one configuration source
          to avoid conflicting effective settings.
        '';
      }

      {
        assertion =
          !(cfg.configPath != null && cfg.serverAddr != "");

        message = ''
          k3s: `serverAddr` should not be set alongside `configPath`.

          Put the server address in one configuration source to avoid
          conflicting effective settings.
        '';
      }

      {
        assertion =
          !(cfg.configPath != null && cfg.token != "");

        message = ''
          k3s: `token` should not be set alongside `configPath`.

          Put the token in one configuration source to avoid conflicting
          effective settings.
        '';
      }

      {
        assertion =
          !(cfg.configPath != null && cfg.tokenFile != null);

        message = ''
          k3s: `tokenFile` should not be set alongside `configPath`.

          Put the token file in one configuration source to avoid conflicting
          effective settings.
        '';
      }
    ];

    environment.systemPackages =
      [ cfg.package ]
      ++ lib.optionals (cfg.role == "server") [
        pkgs.etcd
        k3sEtcdctl
        k3sEtcdHealth
        k3sEtcdStatus
        k3sEtcdMembers
        k3sEtcdRequireHealthy
      ];

    systemd.services.k3s = {
      description = "K3s service";

      after = [
        "firewall.service"
        "network-online.target"
      ];

      wants = [
        "firewall.service"
        "network-online.target"
      ];

      wantedBy = [
        "multi-user.target"
      ];

      path =
        lib.optional
          config.boot.zfs.enabled
          config.boot.zfs.package;

      serviceConfig =
        {
          # K3s agents do not use systemd readiness notification. Servers do.
          Type =
            if cfg.role == "agent" then
              "exec"
            else
              "notify";

          KillMode = "process";
          Delegate = "yes";

          Restart = "always";
          RestartSec = "5s";

          LimitNOFILE = 1048576;
          LimitNPROC = "infinity";
          LimitCORE = "infinity";
          TasksMax = "infinity";

          EnvironmentFile = cfg.environmentFile;

          ExecStartPre = activateK3sContent;
          ExecStart = startK3sScript;
        }
        // lib.optionalAttrs (cfg.role == "server") {
          /*
            A newly added embedded-etcd member may need additional time to
            receive and apply its initial datastore snapshot before K3s sends
            its systemd readiness notification.
          */
          TimeoutStartSec = "300s";
        };
    };
  };

  meta.maintainers = lib.teams.k3s.members;
}