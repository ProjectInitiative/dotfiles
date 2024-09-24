{ nixpkgs, system, ssh-pub-keys }:

{ name, extraModules ? [] }:

nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit ssh-pub-keys; };
  modules = [
    # "${nixpkgs}/nixos/modules/virtualisation/proxmox-lxc.nix"
    ./template.nix
    # ../../hosts/common/configuration.nix

    { virtualisation.lxc.enable = true; }
    # { virtualisation.lxc.lxcfs.enable = true; }
    # { proxmoxLXC.enable = true; }
  ] ++ extraModules;
}
