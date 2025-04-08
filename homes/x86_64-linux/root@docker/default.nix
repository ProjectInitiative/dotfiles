{ lib, ... }:
{

  projectinitiative = {
      home = {
        enable = true;
        stateVersion = "24.11";
      };

      suites = {
        terminal-env.enable = true;
      };

      cli-apps = {
        zsh.enable = true;
        nix.enable = true;
        home-manager.enable = true;
      };
  };
}
