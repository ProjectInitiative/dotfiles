{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.cli-apps.helix;
in
{
  options.${namespace}.cli-apps.helix = with types; {
    enable = mkBoolOpt false "Whether or not to enable common helix editor and language servers.";
  };

  config = mkIf cfg.enable {
    # programs.zsh.shellAliases = {
    # };

    home = {
      packages = with pkgs; [
        helix
        # language servers
        lsp-ai
        nil
        nixd
        python312Packages.python-lsp-server
        python311Packages.python-lsp-server
        pyright
      ];
    };
    # environment.systemPackages = with pkgs; [
    # ];
  };
}
