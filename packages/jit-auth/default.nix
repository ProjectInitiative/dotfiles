{
  lib,
  stdenv,
  bash,
  bitwarden-cli,
  kubectl,
  kubectx,
  k9s,
  kubevirt,
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
  # Optional OpenBao namespace (BAO_NAMESPACE). Exported only when set.
  baoNamespace ? "",
}:

# jit-auth — temporary authenticated development shells.
#
#   auth <app> [<app>...]  dynamic composer: combine ANY subset of apps into
#                          one session — single bw unlock, one fetch per
#                          item, all wrapper sets on PATH, exit destroys
#                          everything. Apps are registered by build-time
#                          fragment files (auth-fragments/<app>.sh).
#   <app>-auth             single-app shortcut (execs `auth <app>`).
#   jit-auth-run           core: unlock bw once, fetch EVERY item once,
#                          start one jit-auth-broker PER SECRET SLOT (each
#                          owns ONE session-lifetime mutable memfd), spawn
#                          $SHELL with session PATH wrappers, clean up.
#   jit-auth-broker        python helper: holds one secret in an anonymous
#                          RAM-only memfd; every wrapped invocation receives
#                          a fresh open-file description of that SAME memfd
#                          over SCM_RIGHTS (independent offsets, shared
#                          mutable content) — kubectx/kubens rewrites
#                          persist for the session without any named file.
#                          Bindings: --env VAR -> VAR=/proc/self/fd/N;
#                          --env-value VAR -> VAR=<literal content>.
#
# App registry (secrets slot, wrapped commands, bindings):
#   k8s     kubectl kubectx kubens k9s virtctl  (KUBECONFIG=/proc/self/fd/N)
#   rclone  rclone                      (RCLONE_CONFIG=/proc/self/fd/N)
#   sops    sops                        (SOPS_AGE_KEY_FILE=/proc/self/fd/N,
#                                        secure note = raw age secret key)
#   bao     bao                         (BAO_TOKEN=<literal>, BAO_ADDR +
#                                        optional BAO_NAMESPACE static)
# e.g. `auth bao k8s` = openbao + k8s in one shell with ONE unlock.
let
  k8sWrappers = "kubectl:${kubectl}/bin/kubectl kubectx:${kubectx}/bin/kubectx kubens:${kubectx}/bin/kubens k9s:${k9s}/bin/k9s virtctl:${kubevirt}/bin/virtctl";
  k8sBindings = "kubectl:KUBECONFIG=k8s kubectx:KUBECONFIG=k8s kubens:KUBECONFIG=k8s k9s:KUBECONFIG=k8s virtctl:KUBECONFIG=k8s";
  baoStaticEnv = lib.concatStringsSep "\n" (
    lib.filter (l: l != "") [
      (lib.optionalString (baoAddress != "") ''export BAO_ADDR="${baoAddress}"'')
      (lib.optionalString (baoNamespace != "") ''export BAO_NAMESPACE="${baoNamespace}"'')
    ]
  );
  # App registry: slot:BW_ITEM secrets, cmd:/abs/path wrappers,
  # cmd:VAR[=+]<slot> bindings, required static env names, static exports.
  # One fragment + one <app>-auth shortcut generated per app.
  apps = {
    k8s = {
      secrets = "k8s:${k8sBitwardenItem}";
      wrappers = k8sWrappers;
      bindings = k8sBindings;
      requiredEnv = "";
      staticEnv = "";
    };
    rclone = {
      secrets = "rclone:${rcloneBitwardenItem}";
      wrappers = "rclone:${rclone}/bin/rclone";
      bindings = "rclone:RCLONE_CONFIG=rclone";
      requiredEnv = "";
      staticEnv = "";
    };
    sops = {
      secrets = "sops:${sopsBitwardenItem}";
      wrappers = "sops:${sops}/bin/sops";
      bindings = "sops:SOPS_AGE_KEY_FILE=sops";
      requiredEnv = "";
      staticEnv = "";
    };
    bao = {
      secrets = "bao:${baoBitwardenItem}";
      wrappers = "bao:${openbao}/bin/bao";
      bindings = "bao:BAO_TOKEN=+bao";
      requiredEnv = "BAO_ADDR";
      staticEnv = baoStaticEnv;
    };
  };
in
stdenv.mkDerivation {
  pname = "jit-auth";
  version = "0.5.0";

  src = ./.;

  nativeBuildInputs = [ ];
  dontUnpack = true;
  dontBuild = true;

  installPhase =
    let
      fragmentCalls = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: a:
          ''make_fragment ${name} "${a.secrets}" "${a.wrappers}" "${a.bindings}" "${a.requiredEnv}" ${lib.escapeShellArg a.staticEnv}''
        ) apps
      );
    in
    ''
      runHook preInstall
      mkdir -p $out/bin/auth-fragments

      install -Dm755 ${./jit-auth-broker} $out/bin/jit-auth-broker
      install -Dm755 ${./jit-auth-run} $out/bin/jit-auth-run
      patchShebangs $out/bin

      # make_fragment <app> <secrets> <wrappers> <bindings> <required_env> <static_env>
      # Writes the registry fragment and the single-app <app>-auth shortcut.
      make_fragment() {
        local app="$1" secrets="$2" wrappers="$3" bindings="$4" required_env="$5" static_env="$6"
        # static_env is embedded inside a double-quoted fragment argument and
        # later eval'd by the composer; escape embedded double quotes.
        static_env="''${static_env//\"/\\\"}"
        cat > $out/bin/auth-fragments/$app.sh <<FRAG_EOF
      # jit-auth app registry fragment (generated; identifiers/store paths only)
      jit_auth_register "$app" "$secrets" "$wrappers" "$bindings" "$required_env" "$static_env"
      FRAG_EOF
        cat > $out/bin/$app-auth <<ALIAS_EOF
      #!/usr/bin/env bash
      exec "$out/bin/auth" "$app" "\$@"
      ALIAS_EOF
        chmod +x $out/bin/$app-auth
      }

      ${fragmentCalls}

      # auth — the dynamic composer (source of the usage list comes from the
      # fragments themselves, so new apps appear automatically).
      substitute ${./auth.sh.in} $out/bin/auth \
        --subst-var out \
        --subst-var-by bitwardenCli ${bitwarden-cli}
      chmod +x $out/bin/auth

      # jit-auth-ls — introspection helper: lists registered apps and one-shot
      # helpers. Self-locating (no substitution); prints identifiers only,
      # never secret contents.
      install -Dm755 ${./jit-auth-ls} $out/bin/jit-auth-ls

      runHook postInstall
    '';

  passthru = {
    apps = lib.attrNames apps;
  };

  meta = with lib; {
    description = "Bitwarden-backed temporary authenticated shells: dynamic `auth <app>...` composer (k8s, rclone, sops, bao)";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "auth";
  };
}
