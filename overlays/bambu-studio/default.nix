{ channels, inputs, ... }:

let
  version = "01.10.01.50";
in
final: prev: {
  bambu-studio = prev.bambu-studio.overrideAttrs (old: {
    version = version;
    src = final.fetchFromGitHub {
      owner = "bambulab";
      repo = "BambuStudio";
      rev = "v${version}";
      hash = "sha256-7mkrPl2CQSfc1lRjl1ilwxdYcK5iRU//QGKmdCicK30=";
    };
  });

}
