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
  cfg = config.${namespace}.cli-apps.pi-coding;
  jsonFormat = pkgs.formats.json { };
  # Strip null values from settings so optional fields don't clutter the JSON
  stripNull = attrs: lib.filterAttrs (n: v: v != null) attrs;
in
{
  options.${namespace}.cli-apps.pi-coding = with types; {
    enable = mkBoolOpt false "Whether to enable pi-coding-agent configuration.";

    agent = {
      instructions = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Content for AGENTS.md — project instructions loaded at startup.
          Tells pi how to extend itself via the Nix module system.
          Other modules can extend this via mkIf/mkMerge.
        '';
      };

      systemPrompt = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Content for SYSTEM.md — system prompt overrides.";
      };

      systemPromptMode = mkOption {
        type = types.enum [ "replace" "append" ];
        default = "append";
        description = "Whether SYSTEM.md replaces or appends to the default prompt.";
      };
    };

    settings = mkOption {
      type = types.nullOr (types.submodule {
        freeformType = jsonFormat.type;
        options = {
          defaultProvider = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default provider (e.g., anthropic, openai).";
          };
          defaultModel = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default model ID.";
          };
          defaultThinkingLevel = mkOption {
            type = types.nullOr (types.enum [ "off" "minimal" "low" "medium" "high" "xhigh" ]);
            default = null;
            description = "Default thinking level for reasoning-capable models.";
          };
          hideThinkingBlock = mkOption {
            type = types.bool;
            default = false;
            description = "Hide thinking blocks in output.";
          };
          theme = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Theme name (dark, light, or custom).";
          };
        };
      });
      default = null;
      description = ''
        Settings to write to ~/.pi/agent/settings.json.
        Any supported pi setting can be included via the freeform type.
        Merges with defaults; set to { } to manage settings with only your values.
      '';
    };

    skills = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this pi skill";

          instructions = mkOption {
            type = types.lines;
            default = "";
            description = "Markdown instructions loaded on-demand when the skill activates.";
          };

          tools = mkOption {
            type = types.attrsOf (types.submodule {
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
            });
            default = { };
            description = "Executable tools provided by this skill.";
          };
        };
      });
      default = { };
      description = ''
        Pi skills — capability packages with instructions and tools, loaded on-demand.
        Other modules can add skills here to extend pi with project-specific knowledge.
        Each skill becomes a directory under ~/.pi/skills/<name>/.
      '';
    };

    extensions = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this pi extension";

          text = mkOption {
            type = types.lines;
            description = "TypeScript source for the extension.";
          };
        };
      });
      default = { };
      description = ''
        Pi extensions — TypeScript modules that extend pi with custom tools,
        commands, event handlers, and UI components.
        Each extension becomes a .ts file under ~/.pi/agent/extensions/<name>.ts.
        Run \`/reload\` in pi after adding or changing extensions.
      '';
    };
  };

  config = mkIf cfg.enable {

    ${namespace}.cli-apps.pi-coding.agent.instructions = mkDefault ''
      # pi self-configuration guide

      Your config is managed by Nix (home-manager). To extend yourself, add skills under
      `projectinitiative.cli-apps.pi-coding.skills.<name>` in any Nix module.

      ## Adding a skill

      ```
      projectinitiative.cli-apps.pi-coding.skills.my-skill = {
        enable = true;
        instructions = "Markdown loaded when this skill activates.";
        tools.my-tool.text = "#!/usr/bin/env bash\necho hello";
      };
      ```

      Generates `~/.pi/skills/<name>/instructions.md` + `~/.pi/skills/<name>/tools/<tool>`.

      ## Adding an extension

      ```
      projectinitiative.cli-apps.pi-coding.extensions.my-ext = {
        enable = true;
        text = builtins.readFile ./path/to/my-extension.ts;
      };
      ```

      Generates `~/.pi/agent/extensions/<name>.ts`. Run `/reload` in pi to activate.

      ## Settings

      ```
      projectinitiative.cli-apps.pi-coding.settings = {
        hideThinkingBlock = true;
        defaultThinkingLevel = "high";
        theme = "dark";
      };
      ```

      Generates `~/.pi/agent/settings.json` with those values.

      ## Extending from another module

      Any Nix module can set these options — other agents can add pi skills or extensions
      by setting their own `projectinitiative.cli-apps.pi-coding.skills.<name>` or
      `projectinitiative.cli-apps.pi-coding.extensions.<name>` block.

      ## Development workflow (faster iteration)

      Instead of rebuilding Nix for every change, use `pi-dev`:

      ```bash
      # Deploy an extension to the writable path for /reload testing
      pi-dev dashboard-footer

      # Watch mode: auto-deploys on file save
      pi-dev peek --watch

      # Deploy + open in editor
      pi-dev permissions --edit
      ```

      Then `/reload` in pi to see changes. When stable, run `nh os switch` to lock it in.

      ## Apply

      Run `home-manager switch` then `/reload` in pi.
    '';

    home.packages = with pkgs; [
      pi-coding-agent
      (writeShellScriptBin "pi-dev" (builtins.readFile ./extensions/pi-dev.sh))
    ];

    home.file =
      # AGENTS.md — project instructions
      (optionalAttrs (cfg.agent.instructions != null) {
        ".pi/agent/AGENTS.md".text = cfg.agent.instructions;
      })

      # SYSTEM.md — system prompt overrides
      // (optionalAttrs (cfg.agent.systemPrompt != null) {
        ".pi/agent/SYSTEM.md".text =
          (if cfg.agent.systemPromptMode == "replace" then "<!-- pi: mode=replace -->\n" else "<!-- pi: mode=append -->\n")
          + cfg.agent.systemPrompt;
      })

      # Settings (~/.pi/agent/settings.json)
      # force = true because pi may have written it first with lastChangelogVersion
      // (optionalAttrs (cfg.settings != null) {
        ".pi/agent/settings.json" = {
          text = builtins.toJSON (stripNull cfg.settings);
          force = true;
        };
      })

      # Skills — capability packages loaded on-demand
      // (foldl' (acc: skillName:
        let
          skill = cfg.skills.${skillName};
        in
        acc // optionalAttrs skill.enable (
          {
            ".pi/skills/${skillName}/instructions.md".text = skill.instructions;
          }
          // mapAttrs' (toolName: tool: {
            name = ".pi/skills/${skillName}/tools/${toolName}";
            value = {
              executable = true;
              text = tool.text;
            };
          }) skill.tools
        )
      ) { } (attrNames cfg.skills))

      # Extensions — TypeScript modules that extend pi
      // (foldl' (acc: extName:
        let
          ext = cfg.extensions.${extName};
        in
        acc // optionalAttrs ext.enable {
          ".pi/agent/extensions/${extName}.ts".text = ext.text;
        }
      ) { } (attrNames cfg.extensions));

  };
}
