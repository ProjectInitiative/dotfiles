{
  lib,
  stdenv,
  python3,
  bash,
  bitwarden-cli,
  kubectl,
  rclone,
  makeWrapper,
  # Bitwarden item identifiers (UUID or name). Identifiers only — secret
  # contents never enter the store. Override from the module once the items
  # exist in the vault.
  k8sBitwardenItem ? "REPLACE-ME",
  rcloneBitwardenItem ? "REPLACE-ME",
}:

# jit-auth — temporary authenticated development shells (k8s-auth, rclone-auth).
#
#   k8s-auth / rclone-auth  frontends: set JIT_* parameters, exec the core
#   jit-auth-run            generic core: unlock bw once, fetch config once,
#                           start in-memory broker, spawn $SHELL, clean up
#   jit-auth-broker         python helper: holds config in RAM, hands a fresh
#                           memfd to each wrapped invocation over SCM_RIGHTS
stdenv.mkDerivation {
  pname = "jit-auth";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    python3
  ];
  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    install -Dm755 ${./jit-auth-broker} $out/bin/jit-auth-broker
    install -Dm755 ${./jit-auth-run} $out/bin/jit-auth-run
    patchShebangs $out/bin

    substitute ${./frontend.sh.in} $out/bin/k8s-auth \
      --subst-var out \
      --subst-var-by session_name k8s \
      --subst-var-by bw_item "${k8sBitwardenItem}" \
      --subst-var-by cmd_name kubectl \
      --subst-var-by config_env KUBECONFIG \
      --subst-var-by real_bin ${kubectl}/bin/kubectl \
      --subst-var-by bitwardenCli ${bitwarden-cli}
    chmod +x $out/bin/k8s-auth

    substitute ${./frontend.sh.in} $out/bin/rclone-auth \
      --subst-var out \
      --subst-var-by session_name rclone \
      --subst-var-by bw_item "${rcloneBitwardenItem}" \
      --subst-var-by cmd_name rclone \
      --subst-var-by config_env RCLONE_CONFIG \
      --subst-var-by real_bin ${rclone}/bin/rclone \
      --subst-var-by bitwardenCli ${bitwarden-cli}
    chmod +x $out/bin/rclone-auth

    runHook postInstall
  '';

  meta = with lib; {
    description = "Bitwarden-backed temporary authenticated shells (k8s-auth, rclone-auth)";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "k8s-auth";
  };
}
