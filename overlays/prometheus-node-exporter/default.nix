{ channels, lib, ... }:

final: prev: {
  prometheus-node-exporter = prev.prometheus-node-exporter.overrideAttrs (oldAttrs: rec {
    version = "unstable-2026-03-12";

    src = final.fetchFromGitHub {
      owner = "prometheus";
      repo = "node_exporter";
      rev = "1a4cac6cc10a009c5b9b2c70459bf6988b06cf64";
      hash = "sha256-bDM7aM09dSr1vba2iUrco04MZIWkqE3QpNa9W61WTgU=";
    };

    # We need to override the vendorHash because the source changed.
    vendorHash = "sha256-nmY/kUvLunAApWAVSKKiKa/aWPlk2imr8ZyFnBLjjUQ=";

    ldflags = [
      "-s"
      "-w"
      "-X github.com/prometheus/common/version.Version=${version}"
      "-X github.com/prometheus/common/version.Revision=1a4cac6"
      "-X github.com/prometheus/common/version.Branch=unknown"
      "-X github.com/prometheus/common/version.BuildUser=nix@nixpkgs"
      "-X github.com/prometheus/common/version.BuildDate=unknown"
    ];
  });
}
