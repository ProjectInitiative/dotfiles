{ channels, inputs, ... }:

let
  version = "1.25.1";
in
final: prev: {
  bcachefs-tools = prev.bcachefs-tools.overrideAttrs (old: {
    version = version;
    src = final.fetchFromGitHub {
      owner = "koverstreet";
      repo = "bcachefs-tools";
      rev = "v${version}";
      hash = "sha256-P6h0n90akgGoFL292UpYTspq1QjcnBDjwvSGyO91xQg=";
    };
  });

}
