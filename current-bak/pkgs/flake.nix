{
  description = "Nixpkgs with custom inputs and overrides";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    helix.url = "github:helix-editor/helix/162028d444b1e56ee39775460adb65e4f957bc3f";
  };
  outputs =
    {
      self,
      nixpkgs,
      helix,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system: {
        default = self.pkgs.${system};
        helix = helix.packages.${system}.default;
      });

      pkgs = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
          overlays = [
            (final: prev: {
              helix = self.packages.${system}.helix;
            })
          ];
        }
      );
      lib = nixpkgs.lib;
    };
}
