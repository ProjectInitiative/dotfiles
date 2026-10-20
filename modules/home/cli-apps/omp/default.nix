# omp (Oh My Pi) coding agent — declarative configuration
#
# Parallel trial with pi-coding-agent (keel OQ-0040). pi stays untouched;
# this module writes ONLY to ~/.omp/, mirroring the pi-coding module's
# option surface so other modules can extend it the same way.
#
# Declarative surfaces:
#   programs.omp.settings  → ~/.omp/agent/config.yml   (TUI + behavior; omp's
#     HM module writes a writable copy so omp's runtime config lock works)
#   ~/.omp/agent/models.yml — custom providers (openai-completions etc.)
#   ~/.omp/agent/mcp.json   — MCP servers (stdio/http/sse per omp types)
#   ~/.omp/agent/extensions/<name>.ts — auto-scanned TS extensions; omp
#     rewrites legacy `@earendil-works/*`/`@mariozechner/*` imports onto its
#     bundled copies, so pi extensions load unmodified
#   ~/.omp/agent/AGENTS.md — global context/instructions
#   ~/.omp/agent/skills/<name>/ — skills (instructions.md + tools/)
#
# NOT ported (follow-ups, see OQ-0040):
#   - npm pi packages (pi-subagents, pi-web-access, pi-mcp-adapter,
#     @hypabolic/crossbar): omp covers these natively (subagents, web tools,
#     native MCP, local-models). context-mode needs its own decision: either
#     an omp plugin (bun state) or a bun2nix store derivation.
#   - pi-dev wrapper: pi-specific dev iteration, not needed for the trial.
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
  cfg = config.${namespace}.cli-apps.omp;

  jsonFormat = pkgs.formats.json { };
  yamlFormat = pkgs.formats.yaml { };

  # Strip null values so optional fields don't clutter the generated files
  stripNull =
    attrs:
    builtins.mapAttrs (
      n: v:
        if builtins.isAttrs v then
          stripNull v
        else if builtins.isList v then
          map (e: if builtins.isAttrs e then stripNull e else e) v
        else
          v
    ) (lib.filterAttrs (n: v: v != null) attrs);

  # omp MCP transports (packages/coding-agent/src/mcp/types.ts):
  #   "stdio" (default), "http" (streamable), "sse".
  # suites.ai "remote" entries in this estate are /sse endpoints → "sse".
  mcpOmpServers = builtins.mapAttrs (
    name: server:
      if server.type == "remote" then
        { type = "sse"; inherit (server) url; }
      else if server.type == "streamable-http" then
        { type = "http"; inherit (server) url; }
      else
        { type = "stdio"; inherit (server) command; inherit (server) args; }
        // lib.optionalAttrs (server.env != { }) { inherit (server) env; }
  ) cfg.mcp.servers;

  mcpJson = {
    "$schema" = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
    mcpServers = mcpOmpServers;
  };

  serverSubmodule = {
    options = {
      enable = mkEnableOption "this MCP server";
      type = mkOption {
        type = types.enum [
          "stdio"
          "remote"
          "streamable-http"
        ];
        description = "MCP transport type (same schema as suites.ai.mcp.servers)";
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
  };
in
{
  # omp's own HM module provides programs.{enable,package,settings} and the
  # writable-copy config.yml activation (handles omp's runtime config lock).
  imports = [ inputs.omp.homeManagerModules.default ];

  options.${namespace}.cli-apps.omp = with types; {
    enable = mkBoolOpt false "Whether to enable omp (Oh My Pi) configuration.";

    agent = {
      instructions = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Content for ~/.omp/agent/AGENTS.md — global instructions loaded at startup.
          Other modules can extend this via mkIf/mkMerge.
        '';
      };

      systemPrompt = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Content for a system-prompt override (see omp system-prompt-customization).";
      };
    };

    settings = mkOption {
      type = types.nullOr (
        types.submodule {
          freeformType = yamlFormat.type;
        }
      );
      default = null;
      description = ''
        Settings written declaratively to ~/.omp/agent/config.yml via
        programs.omp.settings. Any omp setting key is accepted (freeform YAML).
      '';
    };

    models = mkOption {
      type = types.nullOr (
        types.submodule {
          freeformType = yamlFormat.type;
        }
      );
      default = null;
      description = ''
        Custom providers written to ~/.omp/agent/models.yml.
        Schema mirrors pi's models.json (baseUrl, api, apiKey, models,
        modelOverrides). Verify with `omp models <provider>`.
      '';
    };

    mcp = {
      servers = mkOption {
        type = types.attrsOf (types.submodule serverSubmodule);
        default = { };
        description = ''
          MCP servers written to ~/.omp/agent/mcp.json. Pass suites.ai's
          mcp.servers here to share one server definition across agents.
        '';
      };
    };

    skills = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkEnableOption "this omp skill";

            instructions = mkOption {
              type = types.lines;
              default = "";
              description = "Markdown instructions loaded on-demand when the skill activates.";
            };

            tools = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    text = mkOption {
                      type = types.lines;
                      description = "Shell script content for this tool.";
                    };
                    description = mkOption {
                      type = types.str;
                      default = "";
                      description = "Description of this tool's purpose.";
                    };
                  };
                }
              );
              default = { };
              description = "Executable tools provided by this skill.";
            };
          };
        }
      );
      default = { };
      description = ''
        Skills under ~/.omp/agent/skills/<name>/ (instructions.md + tools/).
      '';
    };

    extensions = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkEnableOption "this omp extension";

            text = mkOption {
              type = types.lines;
              description = "TypeScript source for the extension.";
            };
          };
        }
      );
      default = { };
      description = ''
        Extensions — .ts modules under ~/.omp/agent/extensions/<name>.ts.
        Legacy pi imports (@earendil-works/*, @mariozechner/*) are rewritten
        by omp onto its bundled copies. Run /reload-plugins in omp.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.omp = {
      enable = true;
      package = inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings = if cfg.settings != null then stripNull cfg.settings else null;
    };

    # Default AGENTS.md — omp self-config guide + keel charter.
    # Other modules extend via ${namespace}.cli-apps.omp.agent.instructions (mkMerge).
    ${namespace}.cli-apps.omp.agent.instructions = mkMerge [
      # NOTE: plain string, NOT mkDefault — mkDefault-wrapped content gets
      # dropped when merged with mkAfter content (same quirk silently ate the
      # pi module's self-config guide; pi AGENTS.md only has the keel section).
      ''
        # omp self-configuration guide

        Your config is managed by Nix (home-manager). To extend yourself, add
        extensions under `projectinitiative.cli-apps.omp.extensions.<name>` in
        any Nix module. There is no npm/package-manager step — extensions are
        store-managed .ts files in ~/.omp/agent/extensions/.

        ## Adding an extension

        ```
        projectinitiative.cli-apps.omp.extensions.my-ext = {
          enable = true;
          text = builtins.readFile ./path/to/my-extension.ts;
        };
        ```

        Generates `~/.omp/agent/extensions/<name>.ts`. Run `/reload-plugins` in omp.

        ## Adding a skill

        ```
        projectinitiative.cli-apps.omp.skills.my-skill = {
          enable = true;
          instructions = "Markdown loaded when this skill activates.";
          tools.my-tool.text = "#!/usr/bin/env bash\necho hello";
        };
        ```

        ## Settings / models / MCP

        - Settings → `projectinitiative.cli-apps.omp.settings` (freeform YAML →
          `~/.omp/agent/config.yml`)
        - Custom providers → `projectinitiative.cli-apps.omp.models` (→
          `~/.omp/agent/models.yml`); verify with `omp models <name>`
        - MCP servers → `projectinitiative.cli-apps.omp.mcp.servers` (→
          `~/.omp/agent/mcp.json`); the ai suite passes its shared server set

        ## Apply

        Run `nh os switch`, then `/reload-plugins` in omp.
      ''
      # keel — dev-node portfolio grounding (canonical copy: ~/development/keel/ENTRY.md)
      (mkAfter ''
        # keel — project portfolio grounding (two instances: personal + church)

        Two keel instances exist. **Route grounding and write-backs by project estate:**
        - **Personal estate** (`ProjectInitiative` org, this dev node + laptop) → keel at `~/development/keel`
        - **Church estate** (`ACTs-Fellowship-Church` org, mostly on the on-prem node) → keel-church at `~/development/keel-church`

        Read the matching instance's `keel/projects/<id>.md` before working on a project; write records, DEC/OQ/RISK atoms, and events back into the **same instance**. Never mix estate records; cross-estate references are plain URLs, never atom ids. If unsure which estate a project belongs to, check both `keel/projects/` directories before inventing a record — and prefer keel-church for anything ACTs-Fellowship-Church-related.

        Orientation for whichever keel applies (read-only, cheap):
        0. If a git remote is configured, sync first:
           `git -C <keel-dir> pull --ff-only`. On failure (offline, diverged),
           note it and continue locally — advisory, never blocking.
        1. Read `<keel-dir>/AGENTS.md` — the charter and rules of engagement.
        2. Before working on any project, read its record:
           `<keel-dir>/keel/projects/<id>.md` (id = directory name).
        3. For portfolio questions ("what's stale", "what's open"), run
           `<keel-dir>/tools/digest.sh all` — don't guess.

        Write-back (after meaningful work — keep it under a minute):
        4. State changed → update the record (`keel/sop/update.md`).
        5. A durable choice → `keel/decisions/DEC-NNNN-*.md`; an unknown with a working
           default → `keel/open-questions/OQ-NNNN-*.md`; a fragility → `keel/risks/RISK-NNNN-*.md`.
           Copy an existing file as template; ids are zero-padded, continue from highest existing.
        6. Append one line to `keel/events/<year>.md`.
        7. If a git remote is configured, commit all keel changes and `git push` —
           unsynced records are lost context.

        Prime directive: keel is ADVISORY, NEVER BLOCKING. Best-effort records with honest
        `confidence:`; never block delivery. Never edit `views/`. Never invent state you
        didn't observe. Sync failures are noted, never fatal.

        ## Communication preferences (Kyle — applies to ALL projects, both estates)

        - Every copy-paste command must be a **single line** — no backslash
          line-continuations, no multi-line command blocks. One line survives
          terminal formatting and is easier to read and paste.
      '')
    ];

    home.file =
      # AGENTS.md — global instructions
      (optionalAttrs (cfg.agent.instructions != null) {
        ".omp/agent/AGENTS.md".text = cfg.agent.instructions;
      })

      # models.yml — custom providers (real YAML via formats.yaml/remarshal)
      // (optionalAttrs (cfg.models != null) {
        ".omp/agent/models.yml".source = yamlFormat.generate "omp-models.yml" (stripNull cfg.models);
      })

      # mcp.json — MCP servers
      // (optionalAttrs (cfg.mcp.servers != { }) {
        ".omp/agent/mcp.json".text = builtins.toJSON mcpJson;
      })

      # Skills
      // (foldl' (
        acc: skillName:
          let
            skill = cfg.skills.${skillName};
          in
          acc
          // optionalAttrs skill.enable (
            {
              ".omp/agent/skills/${skillName}/instructions.md".text = skill.instructions;
            }
            // mapAttrs' (toolName: tool: {
              name = ".omp/agent/skills/${skillName}/tools/${toolName}";
              value = {
                executable = true;
                text = tool.text;
              };
            }) skill.tools
          )
      ) { } (attrNames cfg.skills))

      # Extensions
      // (foldl' (
        acc: extName:
          let
            ext = cfg.extensions.${extName};
          in
          acc
          // optionalAttrs ext.enable {
            ".omp/agent/extensions/${extName}.ts".text = ext.text;
          }
      ) { } (attrNames cfg.extensions));
  };
}
