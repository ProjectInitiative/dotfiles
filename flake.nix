{
  description = "NixOS configuration with multiple hosts using Snowfall";

  inputs = {
    # NixPkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # NixPkgs Unstable
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-24.11";
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
    sensitiveNotSecretAgeKeys = {
      # url = "git+ssh://root@pikvm/root/sensitive?ref=main";
      url = "git+file:///home/kylepzak/.config/sops/age/sensitive";
      flake = false;
    };

    # Snowfall Lib
    # snowfall-lib.url = "path:/home/kylepzak/development/build-software/snowfall-lib";
    # snowfall-lib.url = "github:projectinitiative/snowfall-lib";
    snowfall-lib.url = "github:snowfallorg/lib?ref=v3.0.3";
    # snowfall-lib.url = "path:/home/short/work/@snowfallorg/lib";
    snowfall-lib.inputs.nixpkgs.follows = "nixpkgs";

    # Avalanche
    avalanche.url = "github:snowfallorg/avalanche";
    # avalanche.url = "path:/home/short/work/@snowfallorg/avalanche";
    avalanche.inputs.nixpkgs.follows = "unstable";

    # Snowfall Flake
    flake.url = "github:snowfallorg/flake?ref=v1.4.1";
    flake.inputs.nixpkgs.follows = "unstable";

    # flake compat
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Snowfall Thaw
    thaw.url = "github:snowfallorg/thaw?ref=v1.0.7";

    # Snowfall Drift
    drift.url = "github:snowfallorg/drift";
    drift.inputs.nixpkgs.follows = "nixpkgs";

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

  };

  outputs =
    inputs:
    let
      lib = inputs.snowfall-lib.mkLib {
        inherit inputs;
        src = ./.;

        snowfall = {
          namespace = "projectinitiative";
          meta = {
            name = "projectinitiative";
            title = "projectinitiative";
          };

        };
      };

    in
    lib.mkFlake {
      # export for debugging
      inherit lib;

      channels-config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          # Add any insecure packages you need
        ];
      };

      overlays = with inputs; [
        flake.overlays.default
        thaw.overlays.default
        drift.overlays.default
      ];
      # modules = {
      #   nixos = lib.snowfall.module.create-modules {
      #     src = lib.snowfall.fs.get-snowfall-file "modules/common";
      #     # namespace = "projectinitiative";
      #   };
      # };

      systems.modules =
        let
          build-modules = lib.create-common-modules "modules/common";
          common-modules = (builtins.attrValues build-modules);
        in
        {
          inherit build-modules common-modules;

          nixos =
            with inputs;
            [
              disko.nixosModules.disko
              home-manager.nixosModules.home-manager
              # nix-ld.nixosModules.nix-ld
              sops-nix.nixosModules.sops
              # agenix.nixosModules.age
              # (import ./encrypted/sops.nix)
            ]
            ++ common-modules;

          darwin =
            with inputs;
            [
              # any darwin specific modules
            ]
            ++ common-modules;
        };

      homes =
        let
          build-modules = lib.create-common-modules "modules/common";
          common-modules = (builtins.attrValues build-modules);
        in
        # build-homes = lib.create-common-modules "modules/common";
        # common-homes = (builtins.attrValues build-homes);
        {
          inherit build-modules common-modules;
          # inherit build-homes common-homes;
          modules =
            with inputs;
            [
              sops-nix.homeManagerModules.sops
              # any home specific modules
            ]
            ++ common-modules;
        };

      # Example host-specific hardware modules
      # systems.hosts.thinkpad.modules = with inputs; [
      #   # Add hardware-specific modules
      #   # Example: nixos-hardware.nixosModules.lenovo-thinkpad-t14
      #   # nixos-hardware.nixosModules.thinkpad-t16-intel-i71260p
      # ];

      deploy = lib.mkDeploy { inherit (inputs) self; };

      checks = builtins.mapAttrs (
        system: deploy-lib: deploy-lib.deployChecks inputs.self.deploy
      ) inputs.deploy-rs.lib;

      outputs-builder = channels: {
        # formatter = channels.nixpkgs.nixfmt-rfc-style;
        # Define the formatter using treefmt-nix
        formatter = (inputs.treefmt-nix.lib.evalModule channels.nixpkgs ./treefmt.nix).config.build.wrapper;

        # Add a check for formatting
        # checks.formatting = (inputs.treefmt-nix.lib.evalModule channels.nixpkgs ./treefmt.nix).config.build.check inputs.self;
      };
    }
    // {
      # Add this line to expose self
      self = inputs.self;
    };
}
