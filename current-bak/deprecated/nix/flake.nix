{
  inputs = {
    nixpkgs = {
      url = "nixpkgs/nixos-unstable";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
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
      packages.x86_64-linux = {
        proxmox-storage-lxc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (import ./template.nix inputs)
            ./configuration.nix
          ];
        };
        proxmox-lxc-template = nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          modules = [
            # you can include your own nixos configuration here, i.e.
            # ./configuration.nix
            (import ./template.nix inputs)
          ];
          format = "proxmox-lxc";
        };
      }; # packages

      nixosConfigurations = {
        # packages.aarch64-linux = {
        lepotato-ha = nixos-generators.nixosGenerate {
          # lepotato-ha = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            # ./sd-image.nix
            (import ./sd-image.nix inputs)
            {
              boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
            }
          ];
          format = "sd-aarch64";
          # buildInputs = with nixpkgs.pkgs; [ gcc-aarch64 binutils-aarch64 ];
        };
      }; # packages

    }; # outputs

} # file closure
