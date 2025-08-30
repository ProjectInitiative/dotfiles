{ channels, inputs, ... }:
# This top-level 'inputs' argument must provide 'flake-compat'.
# It would typically be passed when this overlay file is imported, e.g.,
# (import ./your-overlay.nix { inherit inputs; })
# where 'inputs' comes from your main system flake's inputs.

final: prev: {
  bcachefs-tools =
    let
      # Define the source details for bcachefs-tools
      defaultRev = "da8f1d04e3b89a576cbb5fdd7cd1c1c451be11d8";
      defaultHash = "sha256-N1IGsFwFwLErpi1lAlIKsHfaZ6sahIs7JYG2h6bQ1OA=";

      bcachefsSrc = final.fetchFromGitHub {
        owner = "koverstreet";
        repo = "bcachefs-tools";
        rev = defaultRev;
        hash = defaultHash; # 'hash' is used for SRI hashes like the one provided
      };

      # Use flake-compat to load the flake from the fetched source.
      # 'inputs.flake-compat' must be available from the overlay's arguments.
      bcachefsFlakeOutputs =
        (import inputs.flake-compat {
          src = bcachefsSrc;
        }).defaultNix; # .defaultNix provides an attrset of the flake's outputs

    in
    # Access the desired package. The bcachefs-tools flake you provided
    # exposes 'default' and 'bcachefs-tools' packages per system.
    bcachefsFlakeOutputs.packages.${final.system}.bcachefs-tools;
  # Alternatively, you could use:
  # bcachefsFlakeOutputs.packages.${final.system}.default;
}
