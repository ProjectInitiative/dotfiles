# 
# NIX_BUILD_GROUP_ID=20000000 NIX_FIRST_BUILD_UID=20000000 sh <(curl -L https://nixos.org/nix/install) --daemon
# sudo sytemctl edit nix-daemon.service
# [Service]
# Environment="NIX_SSL_CERT_FILE=/etc/pki/tls/cert.pem"
#
# MacOS:
# { pkgs, config, lib, ... }:
# let
#   CA_BUNDLE = pkgs.runCommandLocal "export-macos-certs-2022-10-14" {} ''
#     # https://stackoverflow.com/questions/40684543/how-to-make-python-use-ca-certificates-from-mac-os-truststore/72053605#72053605
#     (
#       /usr/bin/security export -t certs -f pemseq -k /System/Library/Keychains/SystemRootCertificates.keychain
#       /usr/bin/security export -t certs -f pemseq -k /Library/Keychains/System.keychain
#     ) > $out
#   '';
# in {
#   home = {
#     sessionVariables = {
#       SSL_CERT_FILE = CA_BUNDLE;
#       NIX_SSL_CERT_FILE = CA_BUNDLE;
#       REQUESTS_CA_BUNDLE = CA_BUNDLE;
#     };
#   };

#   accounts.email.accounts."user@example.com" = {
#     imap = {
#       tls.certificatesFile = CA_BUNDLE;
#     };
#   };
# }
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
      chrome = disabled;
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
      ".config/helix/config.toml".source = "${inputs.self}/homes/dotfiles/helix/config.toml";
      ".config/helix/themes".source = "${inputs.self}/homes/dotfiles/helix/themes";
      # ".config/helix/languages.toml".source = helixLanguagesConfig;
      ".alacritty.toml".source = "${inputs.self}/homes/dotfiles/.alacritty.toml";
      ".config/ghostty".source = "${inputs.self}/homes/dotfiles/ghostty";
      ".config/atuin/config.toml".source = "${inputs.self}/homes/dotfiles/atuin/config.toml";
    };
  };

}
