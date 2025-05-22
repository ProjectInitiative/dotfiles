{ channels, inputs, ... }:

let
  bcachefsVersion = "v1.25.2";
  bcachefsRev = "fa0a54c45c44e8ff3885ccc72a43fd2d96e01b14";
  bcachefsSrcHash = "sha256-mmVlGlSW/c7EY7kGzpIEB5mGedNnr3LU1o3M7dOcT0o=";
  bcachefsCargoHash = "sha256-juXRmI3tz2BXQsRaRRGyBaGqeLk2QHfJb2sKPmWur8s=";

in
final: prev: {
  bcachefs-tools = prev.bcachefs-tools.overrideAttrs (
    old:
    let
      # Define the new source *inside* the overrideAttrs block
      newSrc = final.fetchFromGitHub {
        owner = "koverstreet";
        repo = "bcachefs-tools";
        rev = "${bcachefsRev}";
        hash = bcachefsSrcHash;
      };
    in
    {
      version = bcachefsVersion;
      src = newSrc; # Use the source defined above

      cargoDeps = final.rustPlatform.fetchCargoVendor {
        # Pass the *newSrc* to fetchCargoVendor
        src = newSrc;
        # Use the placeholder hash for now
        hash = bcachefsCargoHash;
        # If your rustPlatform expects cargoSha256 instead of hash:
        # cargoSha256 = bcachefsCargoHash;
      };

      # You might need to explicitly bring in other attributes if needed,
      # though often Nixpkgs handles this well. Example:
      # nativeBuildInputs = old.nativeBuildInputs;
      # buildInputs = old.buildInputs;
      # meta = old.meta // { description = old.meta.description + " (overridden)"; };
    }
  );
}
