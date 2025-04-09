# This file defines the structure of your Nix configuration project for Nilla.
# It tells Nilla where to find different types of configurations (systems, homes, modules, etc.).
{
  # List directories containing shared modules or libraries.
  # Nilla will automatically make these available during evaluation.
  includes = [
    ./lib # Your custom library functions (if any)
    ./modules/common # Shared modules for all systems/homes
    ./modules/home # Home Manager specific modules
    ./modules/nixos # NixOS specific modules
    ./modules/darwin # Darwin specific modules (if you have them)
    ./overlays # Your custom overlays
    ./packages # Your custom packages
    # Add other shared directories as needed
  ];

  # Define the locations of your system and home configurations.
  # Nilla uses these paths to find and build your configurations.
  config = {
    # Namespace for your project's specific options and modules.
    # This helps avoid collisions with Nixpkgs or other libraries.
    # Replace 'projectinitiative' with your desired namespace.
    namespace = "projectinitiative";

    # Paths to different types of configurations.
    # Adjust these paths if your directory structure is different.
    systems = ./systems; # Directory containing system configurations (NixOS, Darwin)
    homes = ./homes; # Directory containing Home Manager configurations
    modules = ./modules; # Root directory for all modules (common, nixos, home, etc.)
    packages = ./packages; # Directory for your custom packages
    overlays = ./overlays; # Directory for your overlays
    lib = ./lib; # Directory for your custom library functions

    # You can add more custom paths here if needed by your modules.
    # Example:
    # assets = ./assets;
  };
}
