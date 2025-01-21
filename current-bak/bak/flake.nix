{
  inputs = {
    nixpkgs = {
      url = "nixpkgs/nixos-unstable";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ssh-pub-keys = {
      url = "https://github.com/projectinitiative.keys";
      flake = false;
    };
    # lepotato-nixpkgs.url = "nixpkgs/nixos-unstable";
  };
  # https://blog.nobbz.dev/2022-12-12-getting-inputs-to-modules-in-a-flake/
  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      ssh-pub-keys,
      ...
    }@inputs:
    {
      nixosConfigurations = {
        proxmox-storage-lxc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (import ./template.nix inputs)
            ./configuration.nix
          ];
        };
      };
      nixosConfigurations = {
        lepotato-ha = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            (import ./sd-image.nix inputs)
          ];
        };
      };
      packages.x86_64-linux = {
        proxmox-lxc-template = nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          modules = [
            # you can include your own nixos configuration here, i.e.
            # ./configuration.nix
            (import ./template.nix inputs)
          ];
          format = "proxmox-lxc";
          # optional arguments:
          # explicit nixpkgs and lib:
          # pkgs = nixpkgs.legacyPackages.x86_64-linux;
          # lib = nixpkgs.legacyPackages.x86_64-linux.lib;
          # additional arguments to pass to modules:
          # specialArgs = { myExtraArg = "foobar"; };

          # you can also define your own custom formats
          # customFormats = { "myFormat" = <myFormatModule>; ... };
          # format = "myFormat";
        };
        # vbox = nixos-generators.nixosGenerate {
        #   system = "x86_64-linux";
        #   format = "virtualbox";
        # };
      };
    };
}
