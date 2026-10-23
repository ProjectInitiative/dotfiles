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
  cfg = config.${namespace}.security.sops;
in
{
  options.${namespace}.security.sops = with types; {
    enable = mkBoolOpt false "Whether or not to enable sops.";
  };

  config = mkIf cfg.enable {

    # sops-hostkey-tool is intentionally NOT here: it is a provisioning CLI
    # (guestfish/qemu image manipulation) and dragged libguestfs + guestfs-tools
    # + qemu_kvm into every device toplevel, hanging builds without KVM.
    # It lives in packages/sops-hostkey-tool and the dotfiles devshell instead.
    home = {
      packages = with pkgs; [
        age
        sops
        ssh-to-age
        git-agecrypt
      ];

      shellAliases = {
      };
    };
  };
}
