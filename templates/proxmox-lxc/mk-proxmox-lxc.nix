{ stateVersion, nixpkgs, system, ssh-pub-keys, flakeRoot }:

{ name, extraModules ? [] }:

nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit stateVersion ssh-pub-keys flakeRoot; };
  modules = [
    # "${nixpkgs}/nixos/modules/virtualisation/proxmox-lxc.nix"
    (flakeRoot + "/templates/proxmox-lxc/template.nix")
    # ../../hosts/common/configuration.nix

    { virtualisation.lxc.enable = true; }
    # { virtualisation.lxc.lxcfs.enable = true; }
    # { proxmoxLXC.enable = true; }
  ] ++ extraModules;
}
