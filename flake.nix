{
  description = "NixOS configuration with multiple hosts using Snowfall";

  inputs = {
    # NixPkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # NixPkgs Unstable
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    # home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # macOS Support
    darwin.url = "github:lnl7/nix-darwin/nix-darwin-24.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Hardware Configuration
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # Generate System Images
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    # disko
    # disko.url = "github:nix-community/disko";
    disko.url = "github:projectinitiative/disko";
    # disko.url = "git+file:///home/kylepzak/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    # agenix.url = "github:ryantm/agenix";

    # Nilla (replaces snowfall-lib and related tools)
    nilla.url = "github:projectinitiative/nilla"; # Or your preferred source
    nilla.inputs.nixpkgs.follows = "nixpkgs";

    # Npins (used by nilla for input management)
    npins.url = "github:nix-community/npins";

    # flake compat (keep if needed for non-flake tools)
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Comma (keep if used)
    comma.url = "github:nix-community/comma";
    comma.inputs.nixpkgs.follows = "unstable";

    # System Deployment
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    # Run unpatched dynamically compiled binaries
    nix-ld.url = "github:Mic92/nix-ld";
    nix-ld.inputs.nixpkgs.follows = "unstable";

    # Binary Cache
    attic = {
      url = "github:zhaofengli/attic";

      # FIXME: A specific version of Rust is needed right now or
      # the build fails. Re-enable this after some time has passed.
      inputs.nixpkgs.follows = "unstable";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };

    # Backup management
    icehouse = {
      url = "github:snowfallorg/icehouse?ref=v1.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
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

  };

  outputs = { self, nixpkgs, home-manager, darwin, npins, nilla, ... }@inputs:
    let
      # Define supported systems
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Import npins for managing inputs
      pkgs = npins.pkgs;

      # Define lib using nilla's helper
      lib = nilla.lib {
        inherit pkgs inputs;
        src = ./.; # Point to your flake's root
      };

    in
    # Use nilla's mkFlake to structure the outputs
    lib.mkFlake {
      inherit self inputs; # Pass self and inputs to mkFlake

      # Configure channels (applies overlays, config)
      channels-config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          # Add any insecure packages you need
        ];
      };

      # Define overlays
      overlays = [
        # Add overlays here if needed
        # Example: inputs.my-overlay.overlays.default
      ];

      # Define NixOS configurations using nilla's structure
      nixosConfigurations = {
        # Example structure (replace with your actual hosts)
        # my-nixos-host = lib.mkSystem {
        #   system = "x86_64-linux";
        #   modules = [ ./systems/x86_64-linux/my-nixos-host ];
        # };
        # Add your NixOS hosts here...
        # Example using your previous structure (needs adaptation)
        # stormjib = lib.mkSystem {
        #   system = "aarch64-linux";
        #   modules = [ ./systems/aarch64-linux/stormjib ];
        # };
      };

      # Define Home Manager configurations using nilla's structure
      homeConfigurations = {
        # Example structure (replace with your actual users/configs)
        # "user@hostname" = lib.mkHome {
        #   system = "x86_64-linux";
        #   modules = [ ./homes/x86_64-linux/user ];
        # };
        # Add your Home Manager configurations here...
      };

      # Define Darwin configurations using nilla's structure
      darwinConfigurations = {
        # Example structure (replace with your actual hosts)
        # my-mac = lib.mkDarwin {
        #   system = "aarch64-darwin";
        #   modules = [ ./systems/aarch64-darwin/my-mac ];
        # };
        # Add your Darwin hosts here...
      };

      # Define packages, apps, checks, etc.
      packages = {
        # Add custom packages here
      };

      apps = {
        # Add custom apps here (e.g., for `nix run`)
      };

      checks = {
        # Add checks here (e.g., formatting)
        formatting = (inputs.treefmt-nix.lib.evalModule nixpkgs ./treefmt.nix).config.build.check inputs.self;
      };

      # Define formatter
      formatter = (inputs.treefmt-nix.lib.evalModule nixpkgs ./treefmt.nix).config.build.wrapper;

      # Define devShells if needed
      devShells = {
        # default = pkgs.mkShell { ... };
      };

      # Deployment configuration (if using deploy-rs, adapt as needed)
      # deploy.nodes = { ... }; # Structure might change depending on how nilla integrates

    };
}
