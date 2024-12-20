{
  lib,
  pkgs,
  config,
  osConfig ? { },
  format ? "unknown",
  namespace,
  ...
}:
with lib.${namespace};
{
  projectinitiative = {
    cli-apps = {
      zsh = enabled;
      helix = enabled;
      home-manager = enabled;
    };

    tools = {
      git = enabled;
      direnv = enabled;
    };
  };
}
