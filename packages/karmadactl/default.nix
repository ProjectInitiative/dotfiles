{ lib
, buildGoModule
, fetchFromGitHub
, installShellFiles
}: 

buildGoModule rec {
  pname = "karmadactl";
  version = "1.16.1";

  src = fetchFromGitHub {
    owner = "karmada-io";
    repo = "karmada";
    rev = "v${version}";
    hash = "sha256-Rk5+JXbEXrbbeOijSR4PC+SguYzaSDIzqKeukgQhPBA=";
  };

  vendorHash = null;

  subPackages = [ "cmd/karmadactl" ];

  nativeBuildInputs = [ installShellFiles ];

  ldflags = [
    "-s" "-w"
    "-X github.com/karmada-io/karmada/pkg/version.gitVersion=v${version}"
    "-X github.com/karmada-io/karmada/pkg/version.gitTreeState=clean"
    "-X github.com/karmada-io/karmada/pkg/version.buildDate=1970-01-01T00:00:00Z"
  ];

  doCheck = false;

  postInstall = ''
    export HOME=$(mktemp -d)
    
    # Generate completion files
    $out/bin/karmadactl completion bash > karmadactl.bash
    $out/bin/karmadactl completion zsh > karmadactl.zsh
    $out/bin/karmadactl completion fish > karmadactl.fish

    # Install completion files
    installShellCompletion --cmd karmadactl \
      --bash karmadactl.bash \
      --zsh karmadactl.zsh \
      --fish karmadactl.fish
  '';

  meta = with lib;
    {
      description = "CLI tool for Karmada";
      homepage = "https://github.com/karmada-io/karmada";
      license = licenses.asl20;
      maintainers = with maintainers;
        [ ];
    };
}