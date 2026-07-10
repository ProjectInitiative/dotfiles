{ channels, inputs, ... }:
final: prev: {
  opencode = channels.ai-tools.opencode.overrideAttrs (oldAttrs: {
    version = "1.17.0-custom-model-discovery";
    src = final.fetchFromGitHub {
      owner = "projectinitiative";
      repo = "opencode";
      rev = "f6dfb738c24862e3743e7b5fc01494865ccfd1c8";
      hash = "sha256-5rCAmZMce7SHLb0r4qGp6ZehZJ4PIbmxevRKgcheam8=";
    };
    node_modules = oldAttrs.node_modules.overrideAttrs (_: {
      outputHash = "sha256-9cb02n4vRAiP5Fz8f6jg/l7KNj17cwqYaEoyOuwi9As=";  # Will be provided by nix-build failure message
    });
  });
  inherit (channels.ai-tools) antigravity-cli qwen-code;
}
