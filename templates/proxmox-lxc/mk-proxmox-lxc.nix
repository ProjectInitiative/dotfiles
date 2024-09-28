{ stateVersion, nixpkgs, system, ssh-pub-keys, flakeRoot }:

{ name, extraModules ? [] }:

{
  imports = [
    # "${nixpkgs}/nixos/modules/virtualisation/proxmox-lxc.nix"
    (flakeRoot + "/templates/proxmox-lxc/template.nix")
    # ../../hosts/common/configuration.nix

    { virtualisation.lxc.enable = true; }
    # { virtualisation.lxc.lxcfs.enable = true; }
    # { proxmoxLXC.enable = true; }
  ] ++ extraModules;

  virtualisation.lxc.enable = true;
}
