{ stateVersion, nixpkgs, home-manager, system, ssh-pub-keys, flakeRoot }:

{ name, extraModules ? [] }:

nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit stateVersion ssh-pub-keys flakeRoot; };
  modules = [
    (flakeRoot + "/hosts/common/configuration.nix")
    # Home-manager configuration
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.kylepzak = import (flakeRoot + "/home/kylepzak/home.nix");
      home-manager.extraSpecialArgs = {
        inherit stateVersion flakeRoot;
        # Add any other arguments you want to pass to home.nix
      };
    }

  ] ++ extraModules;

}
