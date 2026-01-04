{
  description = "NixOS configuration with multiple hosts using Snowfall";

  inputs = {
    # NixPkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    #
    # This input will pin the nixpkgs version of unstable until the packages catch
    # up in stable. current trackers: k3s, tailscaled
    # when stable includes: 89c2b2330e733d6cdb5eae7b899326930c2c0648 it is safe to
    # switch
    nixpkgs-catch-up.url = "github:nixos/nixpkgs/nixos-unstable";

    
    # NixPkgs Unstable
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # NixPkgs Master
    upstream.url = "github:nixos/nixpkgs/master";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    # home-manager.url = "github:nix-community/home-manager/release-24.11";
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
      # url = "github:projectinitiative/comin";
      # url = "github:projectinitiative/comin/wip/liveliness-and-bugs";
      url = "github:projectinitiative/comin/wip/manual-rollback";
    };

    # Generate System Images
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    # disko
    disko.url = "github:nix-community/disko";
    # disko.url = "github:projectinitiative/disko/update-device";
    # disko.url = "git+file:///home/kylepzak/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    # agenix.url = "github:ryantm/agenix";

    # Snowfall Lib
    # snowfall-lib.url = "path:/home/kylepzak/dotfiles/vendor/snowfall-lib";
    snowfall-lib.url = "github:projectinitiative/snowfall-lib/pi-lib";
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
    loft = {
      url = "github:projectinitiative/loft";
    };

    attic = {
      url = "github:projectinitiative/attic/feature/updates";
      # url = "path:/home/kylepzak/development/custom-nix/attic";
      # url = "github:zhaofengli/attic";

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

    rockpi-quad = {
      # url = "path:/home/kylepzak/development/build-software/rockpi-quad";
      url = "github:ProjectInitiative/rockpi-quad/wip/convert-to-nix";
      # inputs.nixpkgs.follows = "nixpkgs";
      # inputs.nixos-hardware.follows = "nixos-hardware";
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

  outputs =
    inputs:
    let
      sourcePath = builtins.path {
        path = ./.;
        name = "projectinitiative-source";
      };

      lib = inputs.snowfall-lib.mkLib {
        inherit inputs;
        src = sourcePath;

        snowfall = {
          namespace = "projectinitiative";
          meta = {
            name = "projectinitiative";
            title = "projectinitiative";
          };

        };
      };

      mySrc = sourcePath;

    in
    lib.mkFlake {
      # export for debugging
      inherit lib;
      inherit inputs;
      debuglib = inputs.snowfall-lib.snowfall.internal-lib;
      debugFunctions =
        let
          debuglib = inputs.snowfall-lib.snowfall.internal-lib;
        in
        {
          # List all directories in your systems folder
          listSystemsDirectories =
            let
              systemsPath = "${toString mySrc}/systems";
            in
            builtins.attrNames (builtins.readDir systemsPath);

          # Get target directories for each architecture
          getArchitectureSystems =
            arch:
            let
              systemsPath = "${toString mySrc}/systems/${arch}";
              exists = builtins.pathExists systemsPath;
            in
            if exists then builtins.attrNames (builtins.readDir systemsPath) else [ ];

          # Check if targets have default.nix files
          checkDefaultNix =
            arch: target:
            let
              targetPath = "${toString mySrc}/systems/${arch}/${target}";
              defaultNixPath = "${targetPath}/default.nix";
            in
            builtins.pathExists defaultNixPath;

          # Your actual systems path
          systemsPath = "${toString mySrc}/systems";

          # Add this to your debug functions
          getDetailedSystemMetadata =
            let
              systems_root = "${toString mySrc}/systems";
              targets = debuglib.fs.get-directories systems_root;
              target_paths = builtins.map (t: builtins.unsafeDiscardStringContext t) targets;
            in
            {
              targets = target_paths;
              metadata = builtins.listToAttrs (
                builtins.map (target: {
                  name = builtins.unsafeDiscardStringContext (builtins.baseNameOf target);
                  value = debuglib.system.get-target-systems-metadata target;
                }) targets
              );
            };

          # Debug the create-systems function
          debugCreateSystems =
            let
              systems_root = "${toString mySrc}/systems";
              targets = debuglib.fs.get-directories systems_root;

              # This recreates the internal logic of create-systems
              fix_function = debuglib.internal.system-lib.fix;
              target_systems_metadata = builtins.concatMap (
                target: debuglib.system.get-target-systems-metadata target
              ) targets;
            in
            {
              targets = builtins.map builtins.unsafeDiscardStringContext targets;
              systems_found = target_systems_metadata;
            };

          # And also check the final systems output
          getFinalSystems =
            let
              systems = debuglib.system.create-systems {
                systems = { };
                homes = { };
              };
            in
            builtins.attrNames systems;
        };

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

      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
      ];

      systems = {
        targets = [
          "x86_64-linux"
          "x86_64-darwin"
          "aarch64-linux"
        ];
        hosts = {
          stormjib = {
            system = "aarch64-linux";
          };
        };
        modules =
          let
            build-modules = lib.create-common-modules "modules/common";
            common-modules = (builtins.attrValues build-modules);
          in
          {
            inherit build-modules common-modules;

            nixos =
              with inputs;
              [
                # <<< Add an inline module HERE to disable the nixpkgs one early >>>
                (
                  { config, pkgs, ... }:
                  {
                    # Disable the atticd module provided by the nixpkgs input
                    disabledModules = [ "services/networking/atticd.nix" ];
                  }
                )
                disko.nixosModules.disko
                home-manager.nixosModules.home-manager
                comin.nixosModules.comin
                # nix-ld.nixosModules.nix-ld
                sops-nix.nixosModules.sops
                loft.nixosModules.loft
                # agenix.nixosModules.age
                attic.nixosModules.atticd
                # (import ./encrypted/sops.nix)
                rockpi-quad.nixosModules.rockpi-quad
              ]
              ++ common-modules;

            darwin =
              with inputs;
              [
                # any darwin specific modules
              ]
              ++ common-modules;
          };
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

      deploy = lib.mkDeploy {
        inherit (inputs) self;
        exclude = [
          # "stormjib"
          "thinkpad"
          "test"
          "dinghy"
          "capstan-test"
          "bcachefs-tester"
          "pawl"
          # "cargohold"
          "lightship-atx"
        ];
      };

      checks = builtins.mapAttrs (
        system: deploy-lib: deploy-lib.deployChecks inputs.self.deploy
      ) inputs.deploy-rs.lib;

      outputs-builder = channels: {
        # formatter = channels.nixpkgs.nixfmt-rfc-style;
        # Define the formatter using treefmt-nix
        formatter = (inputs.treefmt-nix.lib.evalModule channels.nixpkgs ./treefmt.nix).config.build.wrapper;

        # Add a check for formatting
        checks.formatting = (inputs.treefmt-nix.lib.evalModule channels.nixpkgs ./treefmt.nix).config.build.check inputs.self;
      };
    }
    // {
      # Add this line to expose self
      self = inputs.self;

      nixOnDroidConfigurations = {
        termux = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
          pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
          modules = [
            ./systems/nix-on-droid/termux/default.nix
          ];
          extraSpecialArgs = {
            namespace = "projectinitiative";
            inputs = inputs;
          };
        };
      };
    };
}
