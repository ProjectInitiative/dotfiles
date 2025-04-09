{ channels, inputs, ... }:

let
  bcachefsVersion = "1.25.1";
  # Hash for the bcachefs-tools source code v1.25.1
  bcachefsSrcHash = "sha256-P6h0n90akgGoFL292UpYTspq1QjcnBDjwvSGyO91xQg=";
  # HASH WILL BE FILLED IN AFTER FIRST FAILED BUILD
  bcachefsCargoHash = "sha256-juXRmI3tz2BXQsRaRRGyBaGqeLk2QHfJb2sKPmWur8s="; # <--- LEAVE THIS EMPTY or use "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
in
final: prev: {
  bcachefs-tools = prev.bcachefs-tools.overrideAttrs (old:
    let
      # Define the new source *inside* the overrideAttrs block
      newSrc = final.fetchFromGitHub {
        owner = "koverstreet";
        repo = "bcachefs-tools";
        rev = "v${bcachefsVersion}";
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
    });
}
