{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.cli-apps.herdr;

  jsonFormat = pkgs.formats.json { };

  # ─── Plugin derivations ──────────────────────────────────────────────────

  herdrMirror = let
    version = "0.1.7";
    binary = pkgs.fetchurl {
      url = "https://github.com/nikok6/herdr-mirror/releases/download/v${version}/herdr-mirror-linux-x86_64";
      hash = "sha256-47IhAeIv9BC+cdV+aoNYDV34bc2KOF9+esPzMUxoBZM=";
    };
    manifest = pkgs.writeText "herdr-mirror-plugin.toml" ''
      id = "mirror"
      name = "Herdr Mirror"
      version = "${version}"
      min_herdr_version = "0.7.2"
      description = "Mirror a remote herdr server's workspaces and agents into the local sidebar"
      platforms = ["linux"]

      [[actions]]
      id = "start"
      title = "Mirror: start / resume"
      command = ["./target/release/herdr-mirror", "start"]

      [[actions]]
      id = "pause"
      title = "Mirror: pause"
      command = ["./target/release/herdr-mirror", "pause"]

      [[actions]]
      id = "status"
      title = "Mirror: status"
      command = ["./target/release/herdr-mirror", "status"]

      [[actions]]
      id = "once"
      title = "Mirror: sync once"
      command = ["./target/release/herdr-mirror", "once"]

      [[actions]]
      id = "remote-new-workspace"
      title = "Mirror: new remote workspace"
      command = ["./target/release/herdr-mirror", "remote-workspace"]

      [[actions]]
      id = "remote-new-tab"
      title = "Mirror: new remote tab"
      command = ["./target/release/herdr-mirror", "remote-tab"]

      [[actions]]
      id = "remote-split-right"
      title = "Mirror: split remote pane right"
      command = ["./target/release/herdr-mirror", "remote-split", "right"]

      [[actions]]
      id = "remote-split-down"
      title = "Mirror: split remote pane down"
      command = ["./target/release/herdr-mirror", "remote-split", "down"]

      [[actions]]
      id = "restore"
      title = "Mirror: restore closed mirrors"
      command = ["./target/release/herdr-mirror", "restore"]

      [[actions]]
      id = "teardown"
      title = "Mirror: teardown"
      command = ["./target/release/herdr-mirror", "teardown"]

      [[events]]
      on = "workspace.focused"
      command = ["./target/release/herdr-mirror", "ensure"]
    '';
  in
    pkgs.runCommand "herdr-mirror-plugin" { } ''
      mkdir -p $out/target/release
      cp ${binary} $out/target/release/herdr-mirror
      chmod +x $out/target/release/herdr-mirror
      cp ${manifest} $out/herdr-plugin.toml
    '';

  # Build the list of enabled plugin entries for plugins.json
  enabledPluginIds = lib.filterAttrs (name: p: p.enable) cfg.plugins;

  pluginJsonEntries = lib.optional (enabledPluginIds ? "mirror") {
    plugin_id = "mirror";
    name = "Herdr Mirror";
    version = "0.1.7";
    min_herdr_version = "0.7.2";
    description = "Mirror a remote herdr server's workspaces and agents into the local sidebar";
    enabled = true;
    platforms = [ "linux" ];
    manifest_path = "/home/kylepzak/.config/herdr/plugins/github/mirror-00154761637c/herdr-plugin.toml";
    plugin_root = "/home/kylepzak/.config/herdr/plugins/github/mirror-00154761637c";
    source = {
      kind = "github";
      owner = "nikok6";
      repo = "herdr-mirror";
      resolved_commit = "0b62363cfdb1d2a0ff72810fd55c9d5d47a1fbd1";
      managed_path = "/home/kylepzak/.config/herdr/plugins/github/mirror-00154761637c";
      installed_unix_ms = builtins.currentTime * 1000;
    };
    build = [{
      command = [ "bash" "scripts/install.sh" ];
    }];
    actions = [
      { id = "start"; title = "Mirror: start / resume"; description = "Start (or resume) the mirror daemon for all configured hosts"; command = [ "./target/release/herdr-mirror" "start" ]; }
      { id = "pause"; title = "Mirror: pause"; description = "Pause syncing"; command = [ "./target/release/herdr-mirror" "pause" ]; }
      { id = "status"; title = "Mirror: status"; command = [ "./target/release/herdr-mirror" "status" ]; }
      { id = "once"; title = "Mirror: sync once"; command = [ "./target/release/herdr-mirror" "once" ]; }
      { id = "teardown"; title = "Mirror: teardown"; command = [ "./target/release/herdr-mirror" "teardown" ]; }
    ];
    events = [{
      on = "workspace.focused";
      command = [ "./target/release/herdr-mirror" "ensure" ];
    }];
  };

  pluginsJson = jsonFormat.generate "plugins.json" pluginJsonEntries;
in
{
  options.${namespace}.cli-apps.herdr = with types; {
    enable = mkBoolOpt false "Whether to enable herdr terminal multiplexer configuration.";

    plugins = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this herdr plugin";
        };
      });
      default = { };
      description = "Herdr plugins to install.";
    };
  };

  config = mkIf cfg.enable {

    home.packages = with pkgs; [
      pkgs.${namespace}.herdr
    ];

    home.file = {
      # Plugin binary + manifest
      ".config/herdr/plugins/github/mirror-00154761637c/target/release/herdr-mirror".source =
        "${herdrMirror}/target/release/herdr-mirror";
      ".config/herdr/plugins/github/mirror-00154761637c/herdr-plugin.toml".source =
        "${herdrMirror}/herdr-plugin.toml";
      # Plugin registry
      ".config/herdr/plugins.json".source = pluginsJson;
    };

  };
}
