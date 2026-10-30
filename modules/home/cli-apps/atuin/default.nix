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
  cfg = config.${namespace}.cli-apps.atuin;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment config
  isHomeManager = options ? home; # Home Manager always has home config

  # Threads and output capture require the daemon; enable it implicitly so
  # callers only need to toggle the feature they actually want.
  daemonEnabled = cfg.daemon.enable || cfg.threads.enable || cfg.outputCapture.enable;

  # Settings carried over from the old homes/dotfiles/atuin/config.toml, plus
  # the feature sections. Anything in cfg.settings wins over these defaults.
  atuinSettings = {
    filter_mode = "global";
    filter_mode_shell_up_key_binding = "host";
    style = "auto";
    inline_height = 0;
    enter_accept = true;
    auto_sync = true;
    sync_address = "https://api.atuin.sh";
    sync_frequency = "10m";
    # The package is managed by Nix; Atuin's self-update notice is noise.
    update_check = false;
    sync.records = true;
  }
  // optionalAttrs daemonEnabled {
    daemon = {
      enabled = true;
      # Atuin starts and supervises the daemon itself (launchd agent on
      # macOS, self-managed process on Linux). Not compatible with
      # systemd socket activation, which we deliberately don't use.
      autostart = true;
    };
  }
  // optionalAttrs cfg.threads.enable {
    threads = {
      capture = true;
      capture_tools = cfg.threads.captureTools;
      filter_mode = cfg.threads.filterMode;
    };
  }
  // optionalAttrs cfg.outputCapture.enable {
    pty_proxy.enabled = true;
    output = {
      enabled = true;
      max_disk_usage = cfg.outputCapture.maxDiskUsage;
    };
  }
  // cfg.settings;

  resumeFlag = optionalString cfg.ai.bindResume " --bind-ai-resume";

  # Idempotent agent integration. `atuin mcp install <agent>` and
  # `atuin hook install <agent>` merge into the agents' own config files
  # (they never overwrite the whole file), and rewrite the nix store path
  # each run so it never goes stale or dangling after a GC.
  agentIntegration = concatStringsSep "\n" (
    map (agent: ''
      if ! ${cfg.package}/bin/atuin mcp install ${agent} >/dev/null; then
        echo "atuin: failed to register MCP server for ${agent}" >&2
      fi
    '') (optional cfg.ai.mcp.enable cfg.ai.mcp.agents)
    ++ map (agent: ''
      if ! ${cfg.package}/bin/atuin hook install ${agent} >/dev/null; then
        echo "atuin: failed to install hooks for ${agent}" >&2
      fi
    '') (optional cfg.ai.agentHooks.enable cfg.ai.agentHooks.agents)
  );

  loginScript = pkgs.writeShellScript "atuin-login" ''
    #!/usr/bin/env bash
    key=$(${pkgs.coreutils}/bin/cat ${cfg.keyPath} | ${pkgs.coreutils}/bin/tr -d $'\n\r')
    ${cfg.package}/bin/atuin login -u ${cfg.username} -p $(${pkgs.coreutils}/bin/cat ${cfg.passwordPath}) -k "$key"
  '';
in
{
  options.${namespace}.cli-apps.atuin = with types; {
    enable = mkBoolOpt false "Whether or not to enable atuin cli.";

    package = mkOption {
      type = types.package;
      default = pkgs.atuin;
      defaultText = "pkgs.atuin";
      description = "The atuin package to use.";
    };

    autoLogin = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to automatically login to the Atuin server on startup.";
    };

    username = mkOption {
      type = types.str;
      description = "The username for the Atuin server.";
    };

    passwordPath = mkOption {
      type = types.str;
      description = "The path to the sops-nix secret containing the Atuin password.";
    };

    keyPath = mkOption {
      type = types.str;
      description = "The path to the sops-nix secret containing the Atuin encryption key.";
    };

    daemon = {
      enable = mkBoolOpt false "Enable the Atuin background daemon (history indexing, threads capture, scheduled sync, output storage). Also enabled implicitly by threads or outputCapture.";
    };

    threads = {
      enable = mkBoolOpt false "Capture AI coding agent sessions (Claude Code, Codex, Copilot, opencode, pi) as encrypted, synced Atuin Threads.";
      captureTools = mkBoolOpt true "Capture tool-call inputs/outputs and file-edit diffs. Atuin redacts recognized secrets and honors history_filter/cwd_filter; disable to record tool names only.";
      filterMode =
        mkOpt
          (types.enum [
            "global"
            "workspace"
            "host"
            "directory"
            "branch"
          ])
          "global"
          "Default filter for the resume picker — global makes sessions from all machines discoverable.";
    };

    outputCapture = {
      enable = mkBoolOpt false "Capture terminal command output via the pty-proxy (stored locally only, never synced).";
      maxDiskUsage =
        mkOpt types.str "2GB"
          "Disk budget for stored output (size, percent of disk, or \"unlimited\").";
    };

    ai = {
      bindResume = mkBoolOpt true "Bind Ctrl+] to `atuin resume` in zsh/bash/fish.";
      mcp = {
        enable = mkBoolOpt false "Register Atuin's built-in MCP server with the listed agents (read-only history/output/threads tools).";
        agents =
          mkOpt (listOf str) [ ]
            "Agents to register: claude-code, codex, copilot, opencode, pi, omp.";
      };
      agentHooks = {
        enable = mkBoolOpt false "Install Atuin's agent command-history hooks into the listed agents' config files.";
        agents = mkOpt (listOf str) [ ] "Agents to hook: claude-code, codex, copilot, opencode, pi.";
      };
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        Extra Atuin config.toml settings. Merged over the module defaults;
        anything set here wins. Written to ~/.config/atuin/config.toml.
      '';
    };
  };

  config = mkIf cfg.enable {

    home.packages = [
      cfg.package
    ];

    # Declarative config.toml (replaces the raw file symlink from
    # modules/home/users/kylepzak). Secrets (key/session) stay outside the
    # store in ~/.local/share/atuin as before.
    xdg.configFile."atuin/config.toml".text = generators.toTOML { } atuinSettings;

    # Enable blesh if bash is enabled
    # https://github.com/akinomyoga/ble.sh/wiki/Manual-A1-Installation#user-content-nixpkgs
    # programs.blesh.enable = mkIf config.programs.bash.enable true;

    # Add shell-specific initialization
    programs.zsh.initContent = mkIf config.programs.zsh.enable ''
      eval "$(atuin init zsh${resumeFlag})"
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      eval "$(atuin init bash${resumeFlag})"
    '';

    programs.fish.shellInit = mkIf config.programs.fish.enable ''
      atuin init fish${resumeFlag} | source
    '';

    # Register Atuin's MCP server and agent hooks with the configured agents.
    # Runs on every home-manager switch: the installers are idempotent, merge
    # instead of overwriting, and refresh the nix store path atuin is invoked
    # with. This is the officially supported way to keep the registration
    # current; there is no declarative config format for these agent files.
    home.activation.atuinAgentIntegration = lib.hm.dag.entryAfter [ "writeBoundary" ] agentIntegration;

    # Pick up config.toml changes in a running daemon (it reloads some
    # settings itself; a restart covers the rest). No-op if not running.
    home.activation.atuinDaemonRestart = lib.hm.dag.entryAfter [ "atuinAgentIntegration" ] ''
      ${cfg.package}/bin/atuin daemon restart >/dev/null 2>&1 || true
    '';

    systemd.user.services.atuin-login = mkIf (cfg.autoLogin && isLinux) {
      Unit = {
        Description = "Atuin login and initial sync";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "oneshot";
        # Force an initial sync after login
        # ExecStartPost = "${cfg.package}/bin/atuin sync --force";
        ExecStart = "${loginScript}";
        RemainAfterExit = true;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };

}
