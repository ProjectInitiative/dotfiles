{
  description = "Nixpkgs with custom inputs and overrides";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Add other external flakes as inputs here
    helix.url = "github:helix-editor/helix/162028d444b1e56ee39775460adb65e4f957bc3f";
    # helix.url = "github:helix-editor/helix";
    # custom-flake.url = "github:user/repo";
  };

  outputs = { self, nixpkgs, helix, ... }: {
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      config = {
        allowUnfree = true;
      };
      overlays = [
        (final: prev: {
          # Example overlay to add a custom package
          # customPackage = custom-flake.packages.x86_64-linux.customPackage;
          # helix = helix.packages.x86_64-linux.helix;
          # helix = helix.packages.${prev.system}.default;
          helix = builtins.trace "Evaluating Helix overlay" (
            builtins.trace "Helix version: ${helix.packages.${system}.default.version}"
            helix.packages.${system}.default
          );

        })
      ];
    };

    lib = nixpkgs.lib;
  };
}
