{ stateVersion, nixpkgs, home-manager, system, ssh-pub-keys, flakeRoot }:

{ name, extraModules ? [] }:

{
  imports = [
    (flakeRoot + "/hosts/common/configuration.nix")
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.kylepzak = import (flakeRoot + "/home/kylepzak/home.nix");
      home-manager.extraSpecialArgs = {
        inherit stateVersion flakeRoot;
      };
    }
  ] ++ extraModules;
}
