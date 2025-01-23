{
  lib,
  pkgs,
  config,
  osConfig ? { },
  format ? "unknown",
  namespace,
  inputs,
  ...
}:
with lib.${namespace};
{

  projectinitiative = {

    home = {
      enable = true;
      stateVersion = "24.11";
    };

    user = {
      enable = true;
    };

    suites = {
      terminal-env = enabled;
      development = enabled;
    };

    cli-apps = {
      zsh = enabled;
      nix = enabled;
      home-manager = enabled;
    };

    security = {
      sops = enabled;
    };

    tools = {
      ghostty = enabled;
    };

    user.authorized-keys = builtins.readFile inputs.ssh-pub-keys;

  };

  # config = {
  #   user.authorized-keys = inputs.ssh-pub-keys;
  # };

  home = {

    file = {
      # ".config/zellij/zellij".source = "${inputs.self}/homes/dotfiles/zellij/zellij";
      ".config/helix/config.toml".source = "${inputs.self}/homes/dotfiles/helix/config.toml";
      ".config/helix/themes".source = "${inputs.self}/homes/dotfiles/helix/themes";
      # ".config/helix/languages.toml".source = helixLanguagesConfig;
      ".alacritty.toml".source = "${inputs.self}/homes/dotfiles/.alacritty.toml";
      ".config/atuin/config.toml".source = "${inputs.self}/homes/dotfiles/atuin/config.toml";
    };
  };

}
