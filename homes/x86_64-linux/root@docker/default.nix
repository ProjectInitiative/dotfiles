{ lib, ... }:
{

  projectinitiative = {
      home = {
        enable = true;
        stateVersion = "24.11";
        home = lib.mkForce "/root";
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
