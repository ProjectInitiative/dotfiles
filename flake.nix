{
  description = "NixOS configuration with multiple hosts using Snowfall";

  inputs = {
    # NixPkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    # NixPkgs Unstable
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Lix
    lix = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.91.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # macOS Support
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Hardware Configuration
    nixos-hardware.url = "github:nixos/nixos-hardware";

    # Generate System Images
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";

    # Snowfall Lib
    snowfall-lib.url = "path:/home/kylepzak/development/build-software/snowfall-lib";
    # snowfall-lib.url = "github:snowfallorg/lib?ref=v3.0.3";
    # snowfall-lib.url = "path:/home/short/work/@snowfallorg/lib";
    snowfall-lib.inputs.nixpkgs.follows = "nixpkgs";

    # Avalanche
    avalanche.url = "github:snowfallorg/avalanche";
    # avalanche.url = "path:/home/short/work/@snowfallorg/avalanche";
    avalanche.inputs.nixpkgs.follows = "unstable";

    # Snowfall Flake
    flake.url = "github:snowfallorg/flake?ref=v1.4.1";
    flake.inputs.nixpkgs.follows = "unstable";

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

  };

  outputs = inputs:
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
          # Add debug information
    debug = {
      raw-files = lib.snowfall.fs.get-nix-files-recursive ./modules/common;
      raw-files-string = toString (lib.snowfall.fs.get-nix-files-recursive ./modules/common);
    };
    in
    lib.mkFlake {
      # export for debugging
      inherit lib;
      inherit debug;

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

          nixos = with inputs; [
            home-manager.nixosModules.home-manager
            nix-ld.nixosModules.nix-ld
            sops-nix.nixosModules.sops
          ] ++ common-modules;

          # home-manager = with inputs; [
          #   # any home-manager specific modules
          # ] ++ common-modules;

          darwin = with inputs; [
            # any darwin specific modules
          ] ++ common-modules;
        };

      homes = 
        let
          build-modules = lib.create-common-modules "modules/common";
          common-modules = (builtins.attrValues build-modules);
        in
        {
          inherit build-modules common-modules;
          modules = with inputs; [
            # any home specific modules
          ] ++common-modules;
        };


      # Example host-specific hardware modules
      # systems.hosts.thinkpad.modules = with inputs; [
      #   # Add hardware-specific modules
      #   # Example: nixos-hardware.nixosModules.lenovo-thinkpad-t14
      #   # nixos-hardware.nixosModules.thinkpad-t16-intel-i71260p
      # ];

      deploy = lib.mkDeploy { inherit (inputs) self; };

      checks = builtins.mapAttrs
        (system: deploy-lib: deploy-lib.deployChecks inputs.self.deploy)
        inputs.deploy-rs.lib;

      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixfmt-rfc-style;
      };
    # };
    } // {
      # Add this line to expose self
      self = inputs.self;
    };
}
