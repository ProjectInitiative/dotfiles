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
  cfg = config.${namespace}.suites.development;
in
{
  options.${namespace}.suites.development = with types; {
    enable = mkBoolOpt false "Whether or not to enable common development configuration.";
  };

  config = mkIf cfg.enable {
    ${namespace} = {
      tools = {
        git = {
            enable = true;
            userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
          };
        direnv = enabled;
        k8s = enabled;
        ansible = enabled;
      };
    };

    security = {
      gpg = enabled;
      sops = enabled;
    };

    home = {
      packages = with pkgs; [
        go
        juicefs
        packer
        podman-compose
        python3
        python3Packages.pip
        rustup
      ];
    };
  };
}
