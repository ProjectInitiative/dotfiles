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
        # TODO: non-host specific items should eventually be removed
        # development.enable = false;
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

    systemd.user.services.generate-ssh-public-key =
      let
        # Write the logic to a separate script file. This avoids all quoting issues.
        script = pkgs.writeShellScript "generate-ssh-pub-key" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          PRIVATE_KEY="$HOME/.ssh/id_ed25519"
          PUBLIC_KEY="$HOME/.ssh/id_ed25519.pub"

          if [ -f "$PRIVATE_KEY" ] && [ ! -s "$PUBLIC_KEY" ]; then
            # Use the full path to the 'echo' command from the coreutils package
            ${pkgs.coreutils}/bin/echo "Generating SSH public key: $PUBLIC_KEY"

            # Use the full path to each command from its respective package
            ${pkgs.openssh}/bin/ssh-keygen -y -f "$PRIVATE_KEY" > "$PUBLIC_KEY.tmp"
            ${pkgs.coreutils}/bin/mv "$PUBLIC_KEY.tmp" "$PUBLIC_KEY"
            ${pkgs.coreutils}/bin/chmod 644 "$PUBLIC_KEY"
          fi
        '';
      in
      {
        Unit = {
          Description = "Generate SSH public key from sops private key";
        };
        Service = {
          Type = "oneshot";
          # Execute the generated script file directly.
          ExecStart = "${script}";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

    programs.zsh.initContent = ''
      if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
        mkdir -p "$HOME/.config/sops/age"
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key "$HOME/.ssh/id_ed25519" > "$HOME/.config/sops/age/keys.txt"
      fi
      export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

    '';

    home = {

      shellAliases = {
        garage = "kubectl exec --context=capstan -n garage -it garage-0 -- /garage";
      };

      file = {
        # Add the directory creation to ensure it exists
        ".config/sops/age/.keep".text = "";
        # ".config/zellij/zellij".source = "${inputs.self}/homes/dotfiles/zellij/zellij";
        ".ssh/id_ed25519".source = config.lib.file.mkOutOfStoreSymlink sops.secrets.kylepzak_ssh_key.path;
        ".config/helix/config.toml".source = "${inputs.self}/homes/dotfiles/helix/config.toml";
        ".config/helix/themes".source = "${inputs.self}/homes/dotfiles/helix/themes";
        # ".config/helix/languages.toml".source = helixLanguagesConfig;
        ".alacritty.toml".source = "${inputs.self}/homes/dotfiles/alacritty.toml";
        ".config/ghostty".source = "${inputs.self}/homes/dotfiles/ghostty";
        ".config/atuin/config.toml".source = "${inputs.self}/homes/dotfiles/atuin/config.toml";
      };
    };

  };

}
