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

  systemd.user.services.setup-sops-age = {
    Unit = {
      Description = "Set up SOPS age key from SSH key";
      After = [ "default.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.config/sops/age";
      ExecStart = "${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i %h/.ssh/id_ed25519 -o %h/.config/sops/age/keys.txt";
      RemainAfterExit = true;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };


  home = {

    file = {
      # Add the directory creation to ensure it exists
      ".config/sops/age/.keep".text = "";
      # ".config/zellij/zellij".source = "${inputs.self}/homes/dotfiles/zellij/zellij";
      ".config/helix/config.toml".source = "${inputs.self}/homes/dotfiles/helix/config.toml";
      ".config/helix/themes".source = "${inputs.self}/homes/dotfiles/helix/themes";
      # ".config/helix/languages.toml".source = helixLanguagesConfig;
      ".alacritty.toml".source = "${inputs.self}/homes/dotfiles/.alacritty.toml";
      ".config/atuin/config.toml".source = "${inputs.self}/homes/dotfiles/atuin/config.toml";
    };
  };

}
