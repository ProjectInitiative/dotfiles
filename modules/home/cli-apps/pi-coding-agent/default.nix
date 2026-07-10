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

      ## Extending from another module

      Any Nix module can set these options — other agents can add pi skills
      by setting their own `projectinitiative.cli-apps.pi-coding.skills.<name>` block.

      ## Apply

      Run `home-manager switch` then `/reload` in pi.
    '';

    home.packages = [ pkgs.pi-coding-agent ];

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
      ) { } (attrNames cfg.skills));

  };
}
