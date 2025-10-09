{ channels, inputs, ... }:
final: prev:
let
  # Import the pinned nixpkgs for this specific package
  oldPkgs = import inputs.nixpkgs-bambu {
    system = final.system;
  };
in
{
  # Use the old nixpkgs’ bambu-studio package directly
  bambu-studio = oldPkgs.bambu-studio;
}
