{
  lib,
  stdenv,
  bash,
  bitwarden-cli,
  kubectl,
  kubectx,
  k9s,
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
#                           start jit-auth-broker (owns ONE session-lifetime
#                           mutable memfd), spawn $SHELL with session PATH
#                           wrappers, clean up on exit
#   jit-auth-broker         python helper: holds the config in an anonymous
#                           RAM-only memfd; every wrapped invocation receives
#                           a fresh open-file description of that SAME memfd
#                           over SCM_RIGHTS (independent offsets, shared
#                           mutable content) — kubectx/kubens rewrites
#                           persist for the session without any named file
#
# Wrapper sets:
#   k8s-auth    kubectl kubectx kubens k9s  (KUBECONFIG=/proc/self/fd/N)
#   rclone-auth rclone                      (RCLONE_CONFIG=/proc/self/fd/N)
stdenv.mkDerivation {
  pname = "jit-auth";
  version = "0.3.0";

  src = ./.;

  nativeBuildInputs = [ ];
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
      --subst-var-by wrappers "kubectl:${kubectl}/bin/kubectl kubectx:${kubectx}/bin/kubectx kubens:${kubectx}/bin/kubens k9s:${k9s}/bin/k9s" \
      --subst-var-by bitwardenCli ${bitwarden-cli}
    chmod +x $out/bin/k8s-auth

    substitute ${./frontend.sh.in} $out/bin/rclone-auth \
      --subst-var out \
      --subst-var-by session_name rclone \
      --subst-var-by bw_item "${rcloneBitwardenItem}" \
      --subst-var-by cmd_name rclone \
      --subst-var-by config_env RCLONE_CONFIG \
      --subst-var-by real_bin ${rclone}/bin/rclone \
      --subst-var-by wrappers "rclone:${rclone}/bin/rclone" \
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
