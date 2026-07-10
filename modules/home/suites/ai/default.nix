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
    };

    mcp = {
      enable = mkBoolOpt true "Configure MCP servers for AI agents.";
    };
  };

  config = mkIf cfg.enable {

    home.packages =
      with pkgs;
      (optional cfg.agent.opencode.enable opencode)
      ++ (optional cfg.agent.antigravity.enable antigravity-cli)
      ++ (optional cfg.agent.qwen.enable qwen-code)
      ++ (optional cfg.agent.claude.enable claude-code)
      ++ (optional cfg.mcp.enable pkgs.${namespace}.mcp-proxy-runner)
      ++ (optional cfg.mcp.enable uv)
      ++ (optionals cfg.mcp.enable [
        poppler
        tesseract
        imagemagick
        exiftool
      ]);

    # ${namespace}.tools.aider = mkIf cfg.agent.aider.enable enabled;

    home.file = {
      ".config/opencode/opencode.json".source = "${inputs.self}/homes/dotfiles/opencode/opencode.json";
    };
  };
}
