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
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.users.kylepzak;
  sops = osConfig.sops;
in
{
  options.${namespace}.users.kylepzak = with types; {
    enable = mkBoolOpt false "Whether or not to enable common user config.";

  };

  config = mkIf cfg.enable {

    projectinitiative = {

      home = {
        enable = true;
      };

      user = {
        enable = true;
      };

      browsers = {
        firefox = enabled;
        chrome = enabled;
        chromium = enabled;
        librewolf = enabled;
        ladybird = disabled;
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
