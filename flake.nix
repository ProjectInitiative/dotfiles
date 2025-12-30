{description = "NixOS configuration with multiple hosts using flake-parts";

  inputs = {
    # NixPkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-catch-up.url = "github:nixos/nixpkgs/nixos-unstable";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    upstream.url = "github:nixos/nixpkgs/master";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # macOS Support
    darwin.url = "github:lnl7/nix-darwin/nix-darwin-24.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Hardware Configuration
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # Package pinning:
    # old nixpkgs just for bambu-studio
    nixpkgs-bambu.url = "github:NixOS/nixpkgs/4697fbbba609";

    # pull in base image builder
    nixos-on-arm = {
      url = "github:projectinitiative/nixos-on-arm";
    };

    wrappers.url = "github:lassulus/wrappers";

    # GitOps
    comin = {
      url = "github:projectinitiative/comin/wip/manual-rollback";
    };

    # Generate System Images
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    # disko
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";

    # Flake Parts
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Comma
    comma.url = "github:nix-community/comma";
    comma.inputs.nixpkgs.follows = "unstable";

    # System Deployment
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    # Run unpatched dynamically compiled binaries
    nix-ld.url = "github:Mic92/nix-ld";
    nix-ld.inputs.nixpkgs.follows = "unstable";

    # Binary Cache
    loft = {
      url = "github:projectinitiative/loft";
    };

    attic = {
      url = "github:projectinitiative/attic/feature/updates";
      inputs.nixpkgs.follows = "unstable";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };

    # formatter
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Yubikey Guide
    yubikey-guide = {
      url = "github:drduh/YubiKey-Guide";
      flake = false;
    };

    # GPG default configuration
    gpg-base-conf = {
      url = "github:drduh/config";
      flake = false;
    };

    # Public SSH keys
    ssh-pub-keys = {
      url = "https://github.com/projectinitiative.keys";
      flake = false;
    };

    # FireFox extentions
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rockpi-quad = {
      url = "github:ProjectInitiative/rockpi-quad/wip/convert-to-nix";
    };

    nixos-avf = {
      url = "github:nix-community/nixos-avf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

  };

  outputs = { self, inputs, ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];

      perSystem = { pkgs, system, lib, ... }: {
        formatter = (inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.wrapper;
        checks.formatting = (inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.check self;
        packages = { };
        devShells = { };
      };

      flake = {
        lib = import ./lib/default.nix {
          inherit inputs self;
        };

        nixosConfigurations = {
          thinkpad = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              inherit inputs self;
              namespace = "projectinitiative";
              myLib = self.lib;
              lib = self.lib;
            };
            modules = [
              ./systems/x86_64-linux/thinkpad
              self.lib.get-common-modules self.lib.flakeDir
              inputs.disko.nixosModules.disko
              inputs.home-manager.nixosModules.home-manager
              inputs.comin.nixosModules.comin
              inputs.sops-nix.nixosModules.sops
              inputs.loft.nixosModules.loft
              inputs.attic.nixosModules.atticd
              inputs.rockpi-quad.nixosModules.rockpi-quad
              ({ config, ... }: {
                disabledModules = [ "services/networking/atticd.nix" ];
              })
            ];
          };
        };

        darwinConfigurations = { };

        homeConfigurations = { };

        deploy.nodes = { };

        nixOnDroidConfigurations = {
          termux = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
            pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
            modules = [
              ./systems/nix-on-droid/termux/default.nix
            ];
            extraSpecialArgs = {
              namespace = "projectinitiative";
              inputs = inputs;
              myLib = self.lib;
            };
          };
        };
      };
    };