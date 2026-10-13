{
  lib,
  stdenv,
  bash,
  bitwarden-cli,
  kubectl,
  kubectx,
  k9s,
  rclone,
  sops,
  openbao,
  # Bitwarden item identifiers (UUID or name). Identifiers only — secret
  # contents never enter the store. Overridden from the module.
  k8sBitwardenItem ? "REPLACE-ME",
  rcloneBitwardenItem ? "REPLACE-ME",
  sopsBitwardenItem ? "REPLACE-ME",
  baoBitwardenItem ? "REPLACE-ME",
  # Internal OpenBao address (BAO_ADDR). An identifier, not a secret — safe
  # for the store; the TOKEN is the secret and lives in Bitwarden.
  baoAddress ? "",
}:

# jit-auth — temporary authenticated development shells (session frontends).
#
#   <name>-auth frontends: set JIT_* parameters, exec the core
#   jit-auth-run           generic core: unlock bw once, fetch EVERY item
#                          once, start one jit-auth-broker PER SECRET SLOT
#                          (each owns ONE session-lifetime mutable memfd),
#                          spawn $SHELL with session PATH wrappers, clean
#                          up on exit. Multiple slots per session = combo
#                          shells (bao-k8s-auth) with a single unlock.
#   jit-auth-broker        python helper: holds one secret in an anonymous
#                          RAM-only memfd; every wrapped invocation receives
#                          a fresh open-file description of that SAME memfd
#                          over SCM_RIGHTS (independent offsets, shared
#                          mutable content) — kubectx/kubens rewrites
#                          persist for the session without any named file.
#                          Bindings: --env VAR -> VAR=/proc/self/fd/N;
#                          --env-value VAR -> VAR=<literal content>.
#
# Wrapper sets (per frontend; bindings in JIT_BINDINGS):
#   k8s-auth      kubectl kubectx kubens k9s  (KUBECONFIG=/proc/self/fd/N)
#   rclone-auth   rclone                      (RCLONE_CONFIG=/proc/self/fd/N)
#   sops-auth     sops                        (SOPS_AGE_KEY_FILE=/proc/self/fd/N,
#                                              secure note = raw age secret key)
#   bao-auth      bao                         (BAO_TOKEN=<literal>, BAO_ADDR static)
#   bao-k8s-auth  bao + kubectl kubectx kubens k9s (both slots, one unlock)
stdenv.mkDerivation {
  pname = "jit-auth";
  version = "0.4.0";

  src = ./.;

  nativeBuildInputs = [ ];
  dontUnpack = true;
  dontBuild = true;

  installPhase =
    let
      k8sWrappers = "kubectl:${kubectl}/bin/kubectl kubectx:${kubectx}/bin/kubectx kubens:${kubectx}/bin/kubens k9s:${k9s}/bin/k9s";
      k8sBindings = "kubectl:KUBECONFIG=k8s kubectx:KUBECONFIG=k8s kubens:KUBECONFIG=k8s k9s:KUBECONFIG=k8s";
      baoAddrLine = lib.optionalString (baoAddress != "") ''export BAO_ADDR="${baoAddress}"'';
    in
    ''
      runHook preInstall
      mkdir -p $out/bin

      install -Dm755 ${./jit-auth-broker} $out/bin/jit-auth-broker
      install -Dm755 ${./jit-auth-run} $out/bin/jit-auth-run
      patchShebangs $out/bin

      # make_frontend <name> <session> <secrets> <wrappers> <bindings> <required_env> <static_env>
      make_frontend() {
        local name="$1" session="$2" secrets="$3" wrappers="$4" bindings="$5" required_env="$6" static_env="$7"
        substitute ${./frontend.sh.in} $out/bin/$name \
          --subst-var out \
          --subst-var-by session_name "$session" \
          --subst-var-by secrets "$secrets" \
          --subst-var-by wrappers "$wrappers" \
          --subst-var-by bindings "$bindings" \
          --subst-var-by required_env "$required_env" \
          --subst-var-by static_env "$static_env" \
          --subst-var-by bitwardenCli ${bitwarden-cli}
        chmod +x $out/bin/$name
      }

      make_frontend k8s-auth k8s \
        "k8s:${k8sBitwardenItem}" \
        "${k8sWrappers}" \
        "${k8sBindings}" \
        "" ""

      make_frontend rclone-auth rclone \
        "rclone:${rcloneBitwardenItem}" \
        "rclone:${rclone}/bin/rclone" \
        "rclone:RCLONE_CONFIG=rclone" \
        "" ""

      make_frontend sops-auth sops \
        "sops:${sopsBitwardenItem}" \
        "sops:${sops}/bin/sops" \
        "sops:SOPS_AGE_KEY_FILE=sops" \
        "" ""

      make_frontend bao-auth bao \
        "bao:${baoBitwardenItem}" \
        "bao:${openbao}/bin/bao" \
        "bao:BAO_TOKEN=+bao" \
        "BAO_ADDR" \
        ${lib.escapeShellArg baoAddrLine}

      make_frontend bao-k8s-auth bao-k8s \
        "bao:${baoBitwardenItem} k8s:${k8sBitwardenItem}" \
        "bao:${openbao}/bin/bao ${k8sWrappers}" \
        "bao:BAO_TOKEN=+bao ${k8sBindings}" \
        "BAO_ADDR" \
        ${lib.escapeShellArg baoAddrLine}

      # jit-auth-ls — introspection helper: lists the generated frontends and
      # their configuration state. Self-locating (no substitution); prints
      # identifiers only, never secret contents.
      install -Dm755 ${./jit-auth-ls} $out/bin/jit-auth-ls

      runHook postInstall
    '';

  meta = with lib; {
    description = "Bitwarden-backed temporary authenticated shells (k8s-auth, rclone-auth, sops-auth, bao-auth, bao-k8s-auth)";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "k8s-auth";
  };
}
