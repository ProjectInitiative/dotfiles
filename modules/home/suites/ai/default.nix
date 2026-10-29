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

  # TensorFold GLM accepts per-request reasoning_effort. Its native levels are
  # low, high, and max; minimal aliases low and medium aliases high.
  glmReasoningOverride = {
    reasoning = true;
    thinkingLevelMap = {
      off = "none";
      minimal = "low";
      low = "low";
      medium = "medium";
      high = "high";
      max = "max";
    };
    input = [
      "text"
      "image"
    ];
    maxTokens = 32768;
    compat = {
      supportsDeveloperRole = false;
      supportsReasoningEffort = true;
      maxTokensField = "max_tokens";
    };
  };

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
  mcpServersJson = builtins.mapAttrs (
    name: server:
    if server.type == "remote" then
      {
        type = "remote";
        url = server.url;
      }
    else if server.type == "streamable-http" then
      {
        type = "streamable-http";
        url = server.url;
      }
    else
      {
        type = "stdio";
        command = server.command;
        args = server.args;
      }
      // lib.optionalAttrs (server.env != { }) { env = server.env; }
  ) enabledServers;

  # Pi MCP config — same servers, different format. Keep each server available
  # through pi-mcp-adapter's single `mcp` proxy tool instead of injecting every
  # server's tool schemas directly into model context.
  # remote → streamable-http SSE (supported by pi-mcp-adapter)
  mcpPiJson = builtins.mapAttrs (
    name: server:
    if server.type == "remote" then
      {
        type = "streamable-http";
        url = server.url;
        directTools = false;
      }
    else
      {
        command = server.command;
        args = server.args;
        directTools = false;
      }
      // lib.optionalAttrs (server.env != { }) { env = server.env; }
  ) enabledServers;

  mcpPiConfig = {
    mcpServers = mcpPiJson;
  };

  # Merge base config with generated MCP section
  fullOpenCodeConfig = baseOpenCodeConfig // {
    mcp = mcpServersJson;
  };

  generatedOpenCodeConfig = jsonFormat.generate "opencode.json" fullOpenCodeConfig;
  generatedMcpConfig = jsonFormat.generate "mcp.json" mcpPiConfig;
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
      # omp (Oh My Pi) — parallel trial with pi (keel OQ-0040). Purely
      # additive: writes only ~/.omp/ while pi keeps ~/.pi/. Flip false to end.
      omp = {
        enable = mkBoolOpt true "Install omp (Oh My Pi) in parallel with pi.";
      };
    };

    mcp = {
      enable = mkBoolOpt true "Configure MCP servers for AI agents.";

      servers = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              enable = mkEnableOption "this MCP server";
              type = mkOption {
                type = types.enum [
                  "stdio"
                  "remote"
                  "streamable-http"
                ];
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
          }
        );
        default = {
          k8s-cc = {
            enable = true;
            type = "remote";
            url = "http://mcp-system-mcp-lb-cc.taildeab2.ts.net/sse";
          };
          # Write-capable agent lanes (agent-access RBAC: jobsmith in llm-test,
          # full namespaced access in agent-sandbox). The MCP tool layer also
          # enforces --allow-namespaces llm-test,agent-sandbox.
          k8s-mc-jobs = {
            enable = true;
            type = "remote";
            url = "http://mcp-system-mcp-lb-mc-jobs.taildeab2.ts.net/sse";
          };
          k8s-cc-jobs = {
            enable = true;
            type = "remote";
            url = "http://mcp-system-mcp-lb-cc-jobs.taildeab2.ts.net/sse";
          };
          k8s-mc = {
            enable = true;
            type = "remote";
            url = "http://mcp-system-mcp-lb-mc.taildeab2.ts.net/sse";
          };
          # Grafana MCP on dinghy — Loki LogQL log query for any host, plus
          # dashboards/alerts read access (token RBAC-scoped on the Grafana
          # side).
          grafana = {
            enable = true;
            type = "remote";
            url = "http://dinghy.taildeab2.ts.net:8000/sse";
          };
          # REA: Reverse Engineer Anything — stdio MCP server from the
          # nix-packaged rea-agents; spawns lazily on first tool call.
          rea = {
            enable = true;
            type = "stdio";
            command = lib.getExe pkgs.${namespace}.rea-agents;
            args = [ "mcp" ];
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
      ++ [ pkgs.${namespace}.ketch ]
      ++ [ pkgs.${namespace}."fifo-proxy" ]
      ++ (optional cfg.mcp.enable pkgs.${namespace}.mcp-proxy-runner)
      ++ (optional cfg.mcp.enable pkgs.${namespace}.rea-agents)
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
          # Always show thinking blocks — no hiding/collapsing.
          hideThinkingBlock = false;
          # pi-mcp-adapter replaces Pi's built-in MCP implementation. Disable
          # the built-in declaratively so the adapter does not try to mutate
          # the Nix-managed, read-only ~/.pi/agent/settings.json at startup.
          extensions = [ "-builtin:mcp" ];
          # Subtle tool backgrounds — near-invisible so boxes don't pop
          # Matches terminal background (#18181e on dark theme)
          toolPendingBg = "#18181e";
          toolSuccessBg = "#18181e";
          toolErrorBg = "#211818";
          toolTitle = "accent";
        };

        # Custom providers — listed here for /login, models auto-discovered by
        # remote-providers extension. A single stub model avoids pi registering
        # an empty stub that would conflict with dynamic discovery.
        models = {
          providers.lemonade = {
            baseUrl = "http://100.81.89.107:13305/v1";
            api = "openai-completions";
          };
          providers.ai = {
            baseUrl = "http://ai.taildeab2.ts.net/v1";
            api = "openai-completions";
            # Virtual key from sops (litellm_virtual_key). Resolved at request
            # time via "!command" — never in the nix store. Empty string until
            # the sops file carries the real key; the gateway ignores auth
            # until the master-key switch (homelab PR #218).
            apiKey = "!cat /run/secrets/litellm_virtual_key 2>/dev/null";
            modelOverrides.dgx-spark = glmReasoningOverride;
          };
          providers.ai-direct = {
            baseUrl = "http://ai-direct.taildeab2.ts.net/v1";
            api = "openai-completions";
            # Second LB to the same authenticated ai-proxy pods — same key.
            apiKey = "!cat /run/secrets/litellm_virtual_key 2>/dev/null";
            modelOverrides.dgx-spark = glmReasoningOverride;
          };
          providers.ai-test = {
            baseUrl = "http://ai-test.taildeab2.ts.net/v1";
            api = "openai-completions";
            # Unauthenticated canary test proxy (ai-proxy-test) — deliberately
            # no key; renamed from ai-gated 2026-10-20.
            modelOverrides.dgx-spark = glmReasoningOverride;
          };
          # astrolabe: disabled until local llama-server comes back up
          # providers.astrolabe = {
          #   baseUrl = "http://100.81.89.107:8080/v1";
          #   api = "openai-completions";
          #   reasoning = true;
          # };
        };
        # Permission gate extension - full spectrum trust levels
        extensions.permissions = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/permissions.ts";
        };

        # Peek extension - toggle thinking block visibility with Ctrl+Shift+H
        # Disabled: thinking should always be visible (hideThinkingBlock = false).
        extensions.peek = {
          enable = false;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/peek.ts";
        };

        # Dashboard footer - rich stats footer with TPS/TFT, trust, and peek status
        extensions.dashboard-footer = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/dashboard-footer.ts";
        };

        # Remote provider discovery - fetches /v1/models at startup for providers
        # configured in models.json without explicit model lists
        extensions.remote-providers = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/remote-providers.ts";
        };

        # Custom tool rendering; starts sessions with tool output expanded.
        extensions.tool-renderer = {
          enable = true;
          text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/tool-renderer.ts";
        };

        # Pi packages from npm — pinned versions, auto-installed on startup
        packages = {
          pi-subagents = {
            enable = true;
            version = "0.81.0";
          };
          pi-web-access = {
            enable = true;
            version = "0.13.0";
          };
          context-mode = {
            enable = true;
            version = "1.0.169";
          };
          pi-mcp-adapter = {
            enable = true;
            # 6.x: pi-ai/pi-tui/typebox moved to peerDependencies (fixes the
            # "host-provided extension packages" warning) and coexists with
            # pi's builtin mcp extension (pi-builtin-mcp.ts). Still reads
            # ~/.pi/agent/mcp.json with directTools.
            version = "6.0.0";
          };
          "@hypabolic/pi-hypa" = {
            enable = true;
            # 1.0.x fixes: rewritten bash commands emitted a bare `hypa` name that
            # bash could not resolve when ~/.local/bin is not on PATH —
            # "line 1: hypa: command not found" (exit 127) on rewritten commands.
            # qualifyRewrittenHypaCommand now fully-qualifies the resolved binary.
            version = "1.0.8";
          };
          # Local model auto-discovery (Ollama, vLLM, LM Studio, etc.)
          # Not needed today — kept for future laptop with local models
          "@hypabolic/crossbar" = {
            enable = true;
            version = "0.5.1";
          };
        };
      };

      # omp (Oh My Pi) — parallel trial (OQ-0040). Mirrors the pi-coding block
      # above; extension sources are shared (same .ts files), MCP servers come
      # from the same `mcp.servers` single source of truth. omp covers
      # pi-subagents/pi-web-access/pi-mcp-adapter/crossbar natively, so no npm
      # packages are needed here — zero lockfiles in the omp path.
      cli-apps.omp = mkIf cfg.agent.omp.enable {
        enable = true;

        settings = {
          hideThinkingBlock = false;
          toolPendingBg = "#18181e";
          toolSuccessBg = "#18181e";
          toolErrorBg = "#211818";
          toolTitle = "accent";
        };

        # Same providers as pi's models.json — GLM reasoning overrides ported
        # verbatim to YAML. Verify with `omp models ai`.
        models = {
          providers.lemonade = {
            baseUrl = "http://100.81.89.107:13305/v1";
            api = "openai-completions";
          };
          providers.ai = {
            baseUrl = "http://ai.taildeab2.ts.net/v1";
            api = "openai-completions";
            # Same sops-backed virtual key as pi (see pi block above).
            apiKey = "!cat /run/secrets/litellm_virtual_key 2>/dev/null";
            modelOverrides.dgx-spark = glmReasoningOverride;
          };
          providers.ai-direct = {
            baseUrl = "http://ai-direct.taildeab2.ts.net/v1";
            api = "openai-completions";
            # Second LB to the same authenticated ai-proxy pods — same key.
            apiKey = "!cat /run/secrets/litellm_virtual_key 2>/dev/null";
            modelOverrides.dgx-spark = glmReasoningOverride;
          };
          providers.ai-test = {
            baseUrl = "http://ai-test.taildeab2.ts.net/v1";
            api = "openai-completions";
            # Unauthenticated canary test proxy (ai-proxy-test) — deliberately
            # no key; renamed from ai-gated 2026-10-20.
            modelOverrides.dgx-spark = glmReasoningOverride;
          };
        };

        # Single source of truth: the same servers pi-mcp-adapter gets.
        # omp transports: stdio | http | sse (remote /sse → sse).
        mcp.servers = enabledServers;

        # Same extension sources as pi — omp rewrites @earendil-works/*
        # imports onto its bundled copies (extension-loading.md).
        extensions.permissions.text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/permissions.ts";
        extensions.permissions.enable = true;
        extensions.dashboard-footer.text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/dashboard-footer.ts";
        extensions.dashboard-footer.enable = true;
        extensions.remote-providers.text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/remote-providers.ts";
        extensions.remote-providers.enable = true;
        extensions.tool-renderer.text = builtins.readFile "${inputs.self}/modules/home/cli-apps/pi-coding-agent/extensions/tool-renderer.ts";
        extensions.tool-renderer.enable = true;

        # context-mode — npm pi-package that ships a NATIVE omp adapter
        # (package.json "omp" manifest; OQ-0040 follow-up). Loaded from the
        # store as a symlink so its relative imports resolve inside the
        # package; its SQLite engine picks bun:sqlite/node:sqlite — the
        # native better-sqlite3 fallback is never reached, so no node_modules
        # or compilation is needed. Under omp the ctx_* tools come via native
        # MCP (server.bundle.mjs under nixpkgs bun) — pi keeps its own
        # extension-based bridge and is untouched.
        extensions.context-mode = {
          enable = true;
          source = "${pkgs.${namespace}.context-mode}/build/adapters/omp/plugin.js";
        };

        mcp.extraServers.context-mode = {
          enable = true;
          type = "stdio";
          command = "${pkgs.bun}/bin/bun";
          args = [ "${pkgs.${namespace}.context-mode}/server.bundle.mjs" ];
        };

        # 8 bundled skills. ctx-upgrade is an npm-imperative flow (no-op on
        # NixOS); kept so the agent doesn't invent its own upgrade path.
        skills = lib.genAttrs
          [
            "context-mode"
            "ctx-doctor"
            "ctx-index"
            "ctx-insight"
            "ctx-purge"
            "ctx-search"
            "ctx-stats"
            "ctx-upgrade"
          ]
          (name: {
            enable = true;
            source = "${pkgs.${namespace}.context-mode}/skills/${name}";
          });
      };

      tools.aider = mkIf cfg.agent.aider.enable enabled;
    };

    # Generate configs with MCP servers injected from config
    home.file = {
      ".config/opencode/opencode.json".source = generatedOpenCodeConfig;
      # pi-mcp-adapter 6.x reads ~/.pi/agent/mcp-adapter.json.
      # Keep every Nix-enabled server available through the mcp proxy.
      ".pi/agent/mcp-adapter.json".source = generatedMcpConfig;
      # Disable pi-web-access curator (no browser available — SSH/headless terminal)
      ".pi/web-search.json".text = builtins.toJSON { workflow = "auto-summary"; };
    };

    # FIFO queue proxy — serializes cheapestinference requests to 1 at a time
    systemd.user.services.fifo-proxy = {
      Unit = {
        Description = "FIFO queue proxy for cheapestinference API";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${(pkgs.${namespace}."fifo-proxy")}/bin/fifo-proxy";
        Restart = "always";
        RestartSec = 3;
        TimeoutStopSec = 10;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };
}
