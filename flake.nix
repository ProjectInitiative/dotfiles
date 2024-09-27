{
  description = "NixOS configuration with multiple hosts";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
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
    # Add other inputs as needed
  };

  outputs = { self, nixpkgs, home-manager, nixos-generators, ssh-pub-keys, ... }@inputs:
    let
      flakeRoot = self;
      system = "x86_64-linux";
      stateVersion = "24.05";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Import the mkProxmoxLXC function
      mkProxmoxLXC = import ./templates/proxmox-lxc/mk-proxmox-lxc.nix {
        inherit stateVersion nixpkgs system ssh-pub-keys flakeRoot;
      };

      mkCommonConfig = import ./hosts/common/mk-common-config.nix {
        inherit stateVersion nixpkgs home-manager system ssh-pub-keys flakeRoot;
      };

      mkLXCCompositeConfig = { name, extraModules ? [] }:
        let
          proxmoxConfig = mkProxmoxLXC {
            inherit name extraModules;
          };
          commonConfig = mkCommonConfig {
            inherit name;
            extraModules = extraModules ++ [proxmoxConfig];
          };
        in commonConfig;
      
    in {
      nixosConfigurations = {
        # Define your hosts here
        thinkpad = mkCommonConfig {
          name = "thinkpad";
          extraModules = [
            ./hosts/thinkpad/configuration.nix
            ./hosts/common/desktop-configuration.nix
          ];
        };

        # test-server = mkLXCCompositeConfig {
        #   name = "test-server";
        #   extraModules = [
        #     ./hosts/test-server/configuration.nix
        #   ];
        # };

        # test-server = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [
        #     (mkProxmoxLXC {
        #       name = "test-server";
        #       extraModules = [];
        #     })
        #     (mkCommonConfig {
        #       name = "test-server";
        #       extraModules = [];
        #     })
        #     ./hosts/test-server/configuration.nix
        #   ];
        # };

        # Base Proxmox LXC template
        proxmox-lxc-base = mkProxmoxLXC { name = "proxmox-lxc-base"; };
       
        # You can add more hosts here
        # another-host = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [
        #     ./configuration.nix
        #     ./hosts/another-host/configuration.nix
        #     home-manager.nixosModules.home-manager
        #     {
        #       home-manager.useGlobalPkgs = true;
        #       home-manager.useUserPackages = true;
        #       home-manager.users.another-user = import ./home.nix;
        #     }
        #   ];
        # };
      }; # nixosConfigurations


      packages.x86_64-linux = {
        proxmox-lxc-template = nixos-generators.nixosGenerate {
          inherit system;
          specialArgs = { inherit ssh-pub-keys; };
          modules = [
            ./templates/proxmox-lxc/template.nix
            # ./hosts/common/configuration.nix
            # { proxmoxLXC.enable = true; }
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
        }; # proxmox-lxc-template

        # vbox = nixos-generators.nixosGenerate {
        #   system = "x86_64-linux";
        #   format = "virtualbox";
        # };
      }; # packages.x86_64-linux

      # Overlay for use in specific server configurations
      # overlays.proxmoxLXC = final: prev: {
      #   proxmoxLXCBase = self.nixosConfigurations.proxmox-lxc-base.config.system.build.toplevel;
      # };
      
    };
}
