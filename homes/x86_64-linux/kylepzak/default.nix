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
  # home.stateVersion = "24.05";
  projectinitiative = {
    cli-apps = {
      zsh = enabled;
      helix = enabled;
      home-manager = enabled;
    };

    tools = {
      git = {
          enable = true;
          userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
        };
      direnv = enabled;
    };
  };
}
