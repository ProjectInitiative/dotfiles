{ channels, inputs, ... }:
# This top-level 'inputs' argument must provide 'flake-compat'.
# It would typically be passed when this overlay file is imported, e.g.,
# (import ./your-overlay.nix { inherit inputs; })
# where 'inputs' comes from your main system flake's inputs.

final: prev: {
  bcachefs-tools =
    let
      # Define the source details for bcachefs-tools
      defaultRev = "f6ed4c26d7bfbb19f5c91f733b65ce6b2e4744f8";
      defaultHash = "sha256-T+DI9Y1+Q5viN96t8Y1PbT77Jw+ZZaC2sn+q4fmAUN8=";

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
