{ channels, inputs, ... }:
final: prev: {
  opencode = channels.ai-tools.opencode.overrideAttrs (oldAttrs: {
    version = "1.15.10-pr-32731";
    src = final.fetchFromGitHub {
      owner = "anomalyco";
      repo = "opencode";
      rev = "450ac3754f76cca981eeb6950fd4702bc47c9619";
      hash = "sha256-4Z2JtOWGJpskj33n+OulJBQf5CSPZeyzNHKzShgp7yk=";
    };
    node_modules = oldAttrs.node_modules.overrideAttrs (_: {
      outputHash = "sha256-4QarL+3fzfC8usp83w3H337TLSEP38H8kq/oQT3z8Dw=";
    });
  });
  inherit (channels.ai-tools) antigravity-cli qwen-code;
}
