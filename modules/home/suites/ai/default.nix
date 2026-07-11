{
  options,
  config,
  lib,
  pkgs,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.ai;

  jsonFormat = pkgs.formats.json { };

  # Build github-mcp-server wrapper that reads GITHUB_TOKEN from sops at runtime
  githubMcpWrapper = pkgs.writeShellScriptBin "github-mcp-server" ''
    export GITHUB_TOKEN="$(cat /run/secrets/github_pat)"
    exec ${pkgs.github-mcp-server}/bin/github-mcp-server "$@"
  '';

  # Read base opencode config (providers, permissions, agents, compaction)
  baseOpenCodeConfig = builtins.fromJSON (
    builtins.readFile "${inputs.self}/homes/dotfiles/opencode/opencode.json"
  );

  # Collect enabled MCP servers
  enabledServers = lib.filterAttrs (name: server: server.enable) cfg.mcp.servers;

  # Transform server definitions into opencode MCP format
  mcpServersJson = builtins.mapAttrs (name: server:
    if server.type == "remote" then {
      type = "remote";
      url = server.url;
    } else if server.type == "streamable-http" then {
      type = "streamable-http";
      url = server.url;
    } else {
      type = "stdio";
      command = server.command;
      args = server.args;
    } // lib.optionalAttrs (server.env != { }) { env = server.env; }
  ) enabledServers;

  # Merge base config with generated MCP section
  fullOpenCodeConfig = baseOpenCodeConfig // {
    mcp = mcpServersJson;
  };

  generatedOpenCodeConfig = jsonFormat.generate "opencode.json" fullOpenCodeConfig;
in
{
  options.${namespace}.suites.ai = with types; {
    enable = mkBoolOpt false "Whether or not to enable AI agent tooling.";

    agent = {
      opencode = {
        enable = mkBoolOpt true "Install the opencode AI coding agent.";
      };
      antigravity = {
        enable = mkBoolOpt true "Install the antigravity-cli agent.";
      };
      qwen = {
        enable = mkBoolOpt true "Install qwen-code agent.";
      };
      claude = {
        enable = mkBoolOpt true "Install claude-code agent.";
      };
      aider = {
        enable = mkBoolOpt true "Install aider agent.";
      };
      pi-coding = {
        enable = mkBoolOpt true "Install pi-coding-agent.";
      };
    };

    mcp = {
      enable = mkBoolOpt true "Configure MCP servers for AI agents.";

      servers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            enable = mkEnableOption "this MCP server";
            type = mkOption {
              type = types.enum [ "stdio" "remote" "streamable-http" ];
              description = "MCP transport type";
            };
            url = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "URL for remote/streamable-http servers";
            };
            command = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Command for stdio servers";
            };
            args = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Arguments for stdio servers";
            };
            env = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "Environment variables for stdio servers";
            };
          };
        });
        default = {
          k8s-cc = {
            enable = true;
            type = "remote";
            url = "http://100.90.79.119/sse";
          };
          k8s-mc = {
            enable = true;
            type = "remote";
            url = "http://100.85.160.67/sse";
          };
        };
        description = "MCP server configurations. Each attr name is the MCP server identifier.";
      };
    };
  };

  config = mkIf cfg.enable {

    home.packages =
      with pkgs;
      (optional cfg.agent.opencode.enable opencode)
      ++ (optional cfg.agent.antigravity.enable antigravity-cli)
      ++ (optional cfg.agent.qwen.enable qwen-code)
      ++ (optional cfg.agent.claude.enable claude-code)
      ++ (optional cfg.agent.aider.enable pkgs.aider-chat)
      ++ (optional cfg.mcp.enable pkgs.${namespace}.mcp-proxy-runner)
      ++ (optional cfg.mcp.enable githubMcpWrapper)
      ++ (optional cfg.mcp.enable uv)
      ++ (optionals cfg.mcp.enable [
        poppler
        tesseract
        imagemagick
        exiftool
      ]);

    ${namespace} = {
      cli-apps.pi-coding = mkIf cfg.agent.pi-coding.enable {
        enable = true;

        # Default settings managed by Nix
        settings = {
          hideThinkingBlock = true;
        };

        # Permission gate extension - full spectrum trust levels
        extensions.permissions = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/permissions.ts";
        };

        # Peek extension - toggle thinking block visibility with Ctrl+Shift+H
        extensions.peek = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/peek.ts";
        };

        # Dashboard footer - rich stats footer with TPS/TFT, trust, and peek status
        extensions.dashboard-footer = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/dashboard-footer.ts";
        };

        # Pi packages from npm — pinned versions, auto-installed on startup
        packages = {
        #   pi-subagents = {
        #     enable = true;
        #     version = "0.34.0";
        #   };
        #   pi-web-access = {
        #     enable = true;
        #     version = "0.13.0";
        #   };
        #   context-mode = {
        #     enable = true;
        #     version = "1.0.169";
        #   };
        #   pi-mcp-adapter = {
        #     enable = true;
        #     version = "2.11.0";
        #   };
        #   "@hypabolic/pi-hypa" = {
        #     enable = true;
        #     version = "0.1.10";
        #   };
        };
      };

      tools.aider = mkIf cfg.agent.aider.enable enabled;
    };

    # Generate opencode.json with MCP servers injected from config
    home.file = {
      ".config/opencode/opencode.json".source = generatedOpenCodeConfig;
    };

  };
}
