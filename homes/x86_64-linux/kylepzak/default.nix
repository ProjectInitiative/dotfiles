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

    browsers = {
      firefox = enabled;
      chrome = enabled;
      chromium = enabled;
      tor = enabled;
    };

    suites = {
      terminal-env = enabled;
      development = enabled;
      backup = enabled;
      messengers = enabled;
      digital-creation = enabled;
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

<<<<<<< Updated upstream
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

=======
>>>>>>> Stashed changes
  programs.zsh.initExtra = ''
    if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
      mkdir -p "$HOME/.config/sops/age"
      ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key "$HOME/.ssh/id_ed25519" > "$HOME/.config/sops/age/keys.txt"
    fi
    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
  '';

  home = {

    file = {
      # Add the directory creation to ensure it exists
      ".config/sops/age/.keep".text = "";
      # ".config/zellij/zellij".source = "${inputs.self}/homes/dotfiles/zellij/zellij";
      ".config/helix/config.toml".source = "${inputs.self}/homes/dotfiles/helix/config.toml";
      ".config/helix/themes".source = "${inputs.self}/homes/dotfiles/helix/themes";
      # ".config/helix/languages.toml".source = helixLanguagesConfig;
      ".alacritty.toml".source = "${inputs.self}/homes/dotfiles/.alacritty.toml";
      ".config/ghostty".source = "${inputs.self}/homes/dotfiles/ghostty";
      ".config/atuin/config.toml".source = "${inputs.self}/homes/dotfiles/atuin/config.toml";
    };
  };

}
