{ channels, inputs, ... }:
# This top-level 'inputs' argument must provide 'flake-compat'.
# It would typically be passed when this overlay file is imported, e.g.,
# (import ./your-overlay.nix { inherit inputs; })
# where 'inputs' comes from your main system flake's inputs.

final: prev: {
  bcachefs-tools =
    let
      # Define the source details for bcachefs-tools
      bcachefsRev = "fa0a54c45c44e8ff3885ccc72a43fd2d96e01b14"; # As in your original overlay
      bcachefsSrcHash = "sha256-mmVlGlSW/c7EY7kGzpIEB5mGedNnr3LU1o3M7dOcT0o="; # As in your original overlay

      bcachefsSrc = final.fetchFromGitHub {
        owner = "koverstreet";
        repo = "bcachefs-tools";
        rev = bcachefsRev;
        hash = bcachefsSrcHash; # 'hash' is used for SRI hashes like the one provided
      };

      # Use flake-compat to load the flake from the fetched source.
      # 'inputs.flake-compat' must be available from the overlay's arguments.
      bcachefsFlakeOutputs = (import inputs.flake-compat {
        src = bcachefsSrc;
      }).defaultNix; # .defaultNix provides an attrset of the flake's outputs

    in
    # Access the desired package. The bcachefs-tools flake you provided
    # exposes 'default' and 'bcachefs-tools' packages per system.
    bcachefsFlakeOutputs.packages.${final.system}.bcachefs-tools;
    # Alternatively, you could use:
    # bcachefsFlakeOutputs.packages.${final.system}.default;
}
