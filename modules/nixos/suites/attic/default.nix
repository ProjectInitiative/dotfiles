# ./modules/attic-suite.nix (Minimal Options, Hardcoded Logic)
{
  config,
  lib,
  pkgs,
  namespace, # Use the same default namespace
  ...
}:

with lib;
with lib.${namespace};
let
  # --- Shorthand for Suite Options ---
  cfg = config.${namespace}.suites.attic;
  sops = config.sops;

  # --- Define Your Placeholder/Actual Values Here ---
  # You MUST edit these placeholder values to match your actual setup.
  commonSettings = {
    cacheName = "shipyard";
    serverUrl = "http://capstan3:8080/shipyard";
    publicKey = "shipyard:+gvvIH3ZmgqtUAD54+FOskuHeAaVY1UwV/W5DIbHQ8I=";
    clientApiTokenFile = sops.secrets.attic_client_api_file.path;
    serverEnvironmentFile = sops.secrets.attic_server_env_file.path;
    storageType = "local";
    storagePath = "/mnt/pool/attic-storage/cache";
    listenAddress = "[::]";
    listenPort = 8080;
  };

in
{
  # --- Suite Options ---
  # ONLY these two options are intended for user configuration.
  options.${namespace}.suites.attic = {
    enableClient = mkBoolOpt false "Enable the pre-defined Attic Client configuration for this host.";
    enableServer = mkBoolOpt false "Enable the pre-defined Attic Server configuration for this host.";
    # NO OTHER OPTIONS DEFINED HERE.
  };

  # --- Configuration Logic ---
  # This block applies the hardcoded configurations below when enabled.
  config = mkMerge [

    # === Apply Predefined Client Config if enableClient is true ===
    (mkIf cfg.enableClient {
      # Directly configure the client module's options using the hardcoded values
      ${namespace}.services.attic.client = {
        enable = true; # Enable the underlying client module

        # Use values defined in commonSettings above
        cacheName = commonSettings.cacheName;
        serverUrl = commonSettings.serverUrl;
        publicKey = commonSettings.publicKey;
        apiTokenFile = commonSettings.clientApiTokenFile;

        # Apply desired default client behaviors
        manageNixConfig = true;
        autoLogin = true;
        watchStore.enable = true;
      };
    })

    # === Apply Predefined Server Config if enableServer is true ===
    (mkIf cfg.enableServer {
      # import server secrets
      sops.secrets = mkMerge [
        {
          attic_server_env_file = {
            sopsFile = ../../services/attic-server/secrets.enc.yaml;
          };
        }
      ];
      # Directly configure the server module's options using the hardcoded values
      ${namespace}.services.attic.server = {
        enable = true; # Enable the underlying server module

        # Use values defined in commonSettings above
        environmentFile = commonSettings.serverEnvironmentFile;
        settings = {
          listenAddress = commonSettings.listenAddress;
          listenPort = commonSettings.listenPort;
          # Chunking settings will use defaults from the server module
        };
        storage.type = commonSettings.storageType;
        storage.path = commonSettings.storagePath;

        # Apply desired default server behaviors
        # garbageCollection.enable = true;
        # openFirewall = true;
        manageStorageDir = true;
      };
    })
  ];
}
