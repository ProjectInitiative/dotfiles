{ channels, inputs, ... }:
# This top-level 'inputs' argument must provide 'flake-compat'.
# It would typically be passed when this overlay file is imported, e.g.,
# (import ./your-overlay.nix { inherit inputs; })
# where 'inputs' comes from your main system flake's inputs.

final: prev: {
  bcachefs-tools =
    let
      # Define the source details for bcachefs-tools
      defaultRev = "7d69a303d1c5eafd860c2377a013fd2aaad43ba2";
      defaultHash = "sha256-WkaRd2TWEVRIbhFzlWPyH2ulHVXLQywLrddeBF01TTs=";

      bcachefsSrc = final.fetchFromGitHub {
        owner = "koverstreet";
        repo = "bcachefs-tools";
        rev = defaultRev;
        hash = defaultHash; # 'hash' is used for SRI hashes like the one provided
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
