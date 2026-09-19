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
  cfg = config.${namespace}.services.infisical;

  secretSubmodule = types.submodule {
    options = {
      name = mkOpt types.str "" "The Infisical secret name.";
      secretPath = mkOpt types.str "/" "The Infisical folder/path the secret lives in.";
      path = mkOpt types.str "" "Destination file path to render the secret to.";
      onChange = mkOpt (types.nullOr types.str) null "Command to run when the secret changes.";
    };
  };

  # Universal Auth credentials may be supplied directly (null) or pointed at
  # runtime files. Nothing is embedded in the repo.
  clientIdFile = if cfg.clientIdFile != null then cfg.clientIdFile else "${cfg.credentialsDir}/client-id";
  clientSecretFile = if cfg.clientSecretFile != null then cfg.clientSecretFile else "${cfg.credentialsDir}/client-secret";

  authConfig =
    if cfg.authMethod == "universal-auth" then
      {
        client-id = clientIdFile;
        client-secret = clientSecretFile;
        remove_client_secret_on_read = cfg.removeClientSecretOnRead;
      }
    else
      cfg.authConfig;

  # One tiny template per secret; renders exactly the value with no trailing
  # whitespace so tokens/hashes land byte-for-byte.
  renderTemplate =
    s:
    pkgs.writeText "infisical-${s.name}.tmpl" ''
      {{- with getSecretByName "${cfg.projectId}" "${cfg.environment}" "${s.secretPath}" "${s.name}" }}{{ if .Value }}{{ .Value }}{{ end }}{{- end -}}
    '';

  templateEntries = map (s: {
    source-path = renderTemplate s;
    destination-path = s.path;
    config = {
      polling-interval = cfg.pollingInterval;
    } // optionalAttrs (s.onChange != null) { execute.command = s.onChange; };
  }) cfg.secrets;

  agentConfigFile = (pkgs.formats.yaml { }).generate "infisical-agent.yaml" (
    {
      infisical = {
        address = cfg.address;
        exit-after-auth = false;
        revoke-credentials-on-shutdown = false;
      };
      auth = {
        type = cfg.authMethod;
        config = authConfig;
      };
      templates = templateEntries;
    }
    // cfg.extraConfig
  );

  destinationDirs = unique (map (s: dirOf s.path) cfg.secrets);
in
{
  options.${namespace}.services.infisical = with types; {
    enable = mkBoolOpt false "Whether to run the Infisical Agent on this node.";
    package = mkOpt package pkgs.infisical "The Infisical CLI package to run.";
    address = mkOpt str "https://app.infisical.com" "Infisical instance URL.";
    projectId = mkOpt str "<INFISICAL_PROJECT_ID>" "Infisical project UUID (placeholder).";
    environment = mkOpt str "prod" "Infisical environment slug.";
    authMethod = mkOpt (enum [
      "universal-auth"
      "aws-iam"
      "azure"
      "gcp"
      "kubernetes"
    ]) "universal-auth" "Infisical authentication method.";
    credentialsDir = mkOpt str "/var/lib/infisical" "Directory holding the universal-auth client-id/client-secret files.";
    clientIdFile = mkOpt (nullOr path) null "Explicit path to the file containing the universal-auth client ID.";
    clientSecretFile = mkOpt (nullOr path) null "Explicit path to the file containing the universal-auth client secret.";
    removeClientSecretOnRead = mkBoolOpt false "Delete the client secret file after reading it.";
    authConfig = mkOpt attrs { } "Auth config used for non-universal auth methods.";
    pollingInterval = mkOpt str "5m" "How often the agent checks for secret changes.";
    secrets = mkOpt (listOf secretSubmodule) [ ] "Secrets to render to files.";
    extraConfig = mkOpt attrs { } "Extra attributes merged into the agent config.";
    writablePaths = mkOpt (listOf str) [ ] "Extra paths the agent may write to, in addition to destination directories.";
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules =
      [
        "d /run/secrets 0700 root root -"
        "d ${cfg.credentialsDir} 0700 root root -"
      ]
      ++ map (d: "d ${d} 0700 root root -") destinationDirs;

    systemd.services.infisical-agent = {
      description = "Infisical Agent - render secrets to files at runtime";
      documentation = [ "https://infisical.com/docs/integrations/platforms/infisical-agent" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/infisical agent --config ${agentConfigFile}";
        Restart = "on-failure";
        RestartSec = "15s";

        User = "root";
        Group = "root";

        # Hardening. The agent only needs to read its credentials and write
        # the rendered destinations.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ReadWritePaths = unique (
          [
            "/run/secrets"
            cfg.credentialsDir
          ]
          ++ destinationDirs
          ++ cfg.writablePaths
        );
      };
    };
  };
}
