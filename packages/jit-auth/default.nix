{
  lib,
  stdenv,
  bash,
  bitwarden-cli,
  kubectl,
  rclone,
  # Bitwarden item identifiers (UUID or name). Identifiers only — secret
  # contents never enter the store. Overridden from the module.
  k8sBitwardenItem ? "REPLACE-ME",
  rcloneBitwardenItem ? "REPLACE-ME",
}:

# jit-auth — temporary authenticated development shells (k8s-auth, rclone-auth).
#
#   k8s-auth / rclone-auth  frontends: set JIT_* parameters, exec the core
#   jit-auth-run            generic core: unlock bw once, fetch config once,
#                           materialize it in a RAM-backed session file
#                           ($XDG_RUNTIME_DIR/jit-auth-<session>-<pid>/config,
#                           0600, inside a 0700 dir, removed on exit), export
#                           it as the tool's config env var, spawn $SHELL.
#
# Deviation from the original memfd-per-invocation design: context tools
# (kubectx/kubens) REWRITE the kubeconfig and full-screen tools (k9s) read it
# via $KUBECONFIG, so the session uses one mutable RAM-backed file instead of
# per-invocation memfds. XDG_RUNTIME_DIR is tmpfs (systemd), so the config
# lives in RAM only and vanishes at session end. See jit-auth-run's header.
stdenv.mkDerivation {
  pname = "jit-auth";
  version = "0.2.0";

  src = ./.;

  nativeBuildInputs = [ ];
  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    install -Dm755 ${./jit-auth-run} $out/bin/jit-auth-run
    patchShebangs $out/bin/jit-auth-run

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
