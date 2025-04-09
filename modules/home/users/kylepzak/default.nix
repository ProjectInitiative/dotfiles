{
  lib,
  pkgs,
  config,
  osConfig ? { },
  format ? "unknown",
  # namespace, # No longer needed for helpers
  inputs,
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.users.kylepzak;
  sops = osConfig.sops;
in
{
  options.${namespace}.users.kylepzak = {
    enable = mkEnableOption "common user config."; # Use standard mkEnableOption

  };

  config = mkIf cfg.enable {

    projectinitiative = {

      home = {
        enable = true; # Standard boolean
        stateVersion = "24.11";
      };

      user = {
        enable = true; # Standard boolean
      };

      browsers = {
        firefox.enable = true; # Use standard boolean
        chrome.enable = false; # Use standard boolean
        chromium.enable = true; # Use standard boolean
        librewolf.enable = true; # Use standard boolean
        ladybird.enable = false; # Use standard boolean
        tor.enable = true; # Use standard boolean
      };

      suites = {
        terminal-env.enable = true; # Use standard boolean
        development.enable = true; # Use standard boolean
        backup.enable = true; # Use standard boolean
        messengers.enable = true; # Use standard boolean
        digital-creation.enable = true; # Use standard boolean
      };

      cli-apps = {
        zsh.enable = true; # Use standard boolean
        nix.enable = true; # Use standard boolean
        home-manager.enable = true; # Use standard boolean
      };

      security = {
        sops.enable = true; # Use standard boolean
      };

      tools = {
        ghostty.enable = true; # Use standard boolean
      };

      user.authorized-keys = builtins.readFile inputs.ssh-pub-keys; # Assuming this path is correct

    };

    # config = {
    #   user.authorized-keys = inputs.ssh-pub-keys;
    # };

    # systemd.user.services.setup-sops-age = {
    #   Unit = {
    #     Description = "Set up SOPS age key from SSH key";
    #     After = [ "default.target" ];
    #   };

    #   Service = {
    #     Type = "oneshot";
    #     ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.config/sops/age";
    #     ExecStart = "${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i %h/.ssh/id_ed25519 -o %h/.config/sops/age/keys.txt";
    #     RemainAfterExit = true;
    #   };

    #   Install = {
    #     WantedBy = [ "default.target" ];
    #   };
    # };

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
        ".ssh/id_ed25519".source = config.lib.file.mkOutOfStoreSymlink sops.secrets.kylepzak_ssh_key.path;
        ".config/helix/config.toml".source = "${inputs.self}/homes/dotfiles/helix/config.toml";
        ".config/helix/themes".source = "${inputs.self}/homes/dotfiles/helix/themes";
        # ".config/helix/languages.toml".source = helixLanguagesConfig;
        ".alacritty.toml".source = "${inputs.self}/homes/dotfiles/.alacritty.toml";
        ".config/ghostty".source = "${inputs.self}/homes/dotfiles/ghostty";
        ".config/atuin/config.toml".source = "${inputs.self}/homes/dotfiles/atuin/config.toml";
      };
    };

  };

}
