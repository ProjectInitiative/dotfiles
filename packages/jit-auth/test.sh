#!/usr/bin/env bash
# Lightweight validation for jit-auth (fake credentials only).
# Fakes `bw` and the wrapped tools, then drives the real broker + wrapper
# pipeline through a scripted child shell. Covers: once-per-session fetch
# PER SLOT (multi-secret combo sessions), PATH-wrapper invocation from
# plain/bash/sh children, MUTATION PERSISTENCE via the shared session memfd,
# independent per-client offsets, LITERAL token injection (BAO_TOKEN),
# concurrency, env hygiene, absence of any named config, and exit cleanup.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIT_BIN="${JIT_BIN:-$here/result/bin}"
work="$(mktemp -d /tmp/jit-auth-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail_test() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# --- fake `bw` -----------------------------------------------------------
# Records item fetches to prove once-per-session PER ITEM. Returns distinct
# fake secrets per item (kubeconfig note vs bao token note).
mkdir -p "$work/fakebin"
cat > "$work/fakebin/bw" <<EOF
#!/usr/bin/env bash
case "\$1" in
  status) echo '{"status": "unauthenticated"}' ;;
  login)  echo "fake-session-token" ;;
  unlock) echo "fake-session-token" ;;
  sync)   exit 0 ;;
  get)
    item="\$3"
    echo "\$item" >> "$work/fetch.log"
    case "\$item" in
      fake-k8s-item)  printf 'context: one\nnamespace: default\n' ;;
      fake-bao-item)  printf 'fake-bao-token' ;;
      *)              exit 1 ;;
    esac
    ;;
  *)      exit 1 ;;
esac
EOF
chmod +x "$work/fakebin/bw"

# --- fake wrapped tools --------------------------------------------------
# kubectl: reads KUBECONFIG (/proc/self/fd/N), reports content; the
# "use-context" / "use-namespace" modes MUTATE the file in place (truncate +
# rewrite, like client-go/kubectx do) to verify shared mutable state.
mkdir -p "$work/realbin"
cat > "$work/realbin/kubectl" <<'EOF'
#!/usr/bin/env bash
conf="${KUBECONFIG:?(test) KUBECONFIG not set by wrapper}"
[ -r "$conf" ] || { echo "config unreadable" >&2; exit 1; }
content="$(cat "$conf")"
case "$1" in
  get)
    case "$content" in
      *"current: two"*) echo "ran:get ctx=two" ;;
      *"current: one"*) echo "ran:get ctx=one" ;;
      *) echo "ran:get ctx=unknown" ;;
    esac
    ;;
  use-context)
    printf 'context: one\nnamespace: default\ncurrent: two\n' > "$conf"
    echo "mutated:context"
    ;;
  use-namespace)
    printf 'context: one\nnamespace: kube-system\ncurrent: two\n' > "$conf"
    echo "mutated:namespace"
    ;;
  *) echo "ran:$1" ;;
esac
EOF
chmod +x "$work/realbin/kubectl"

# bao: the token arrives as a LITERAL env value (BAO_TOKEN), the address as
# static config exported into the session shell. Verifies both, then dumps
# its own env so the test can check exactly where the token is visible.
cat > "$work/realbin/bao" <<'EOF'
#!/usr/bin/env bash
[ -n "${BAO_ADDR:?(test) BAO_ADDR not set}" ] || exit 1
[ -n "${BAO_TOKEN:?(test) BAO_TOKEN not set by wrapper}" ] || exit 1
if [ "$BAO_TOKEN" != "fake-bao-token" ]; then echo "WRONG_TOKEN:$BAO_TOKEN"; exit 1; fi
echo "bao:token-ok addr=$BAO_ADDR"
env > "${BAO_TEST_ENV_OUT:?no env dump path}"
EOF
chmod +x "$work/realbin/bao"

# kubectx/kubens/k9s fake binaries: delegate to the same mutation/reporting
# logic so wrapper resolution for these names is exercised too.
for t in kubectx kubens k9s; do
  ln -sf kubectl "$work/realbin/$t"
done

# --- scripted auth session ----------------------------------------------
cat > "$work/session.sh" <<EOF
#!/usr/bin/env bash
# PATH-resolved invocations of each wrapped tool
kubectl get pods
kubectx use-context two
# mutation must be visible to a later, separate child through the SAME memfd
kubectl get pods | grep -q 'ctx=two' || { echo MUTATION_LOST; exit 1; }
kubens use-namespace two
# second mutation still sees the first (state accumulates in one memfd)
kubectl get pods | grep -q 'ctx=two' || { echo MUTATION_LOST; exit 1; }
k9s get pods
bash -c 'kubectl get pods'
sh -c 'kubectl get pods'
# combo slot: literal token reaches the wrapped process
bao status
bash -c 'bao status'
# concurrency: independent offsets, no stream consumption between clients
kubectl get pods & kubectl get svc & wait
env > "$work/child-env.txt"
[ -z "\${BW_SESSION:-}" ] || echo BW_SESSION_LEAK
[ -z "\${KUBECONFIG_RAW:-}" ] || echo KUBECONFIG_RAW_LEAK
[ -z "\${KUBECONFIG:-}" ] || echo GLOBAL_KUBECONFIG_LEAK
[ -z "\${BAO_TOKEN:-}" ] || echo BAO_TOKEN_LEAK
grep -q 'context: one' "$work/child-env.txt" && echo ENV_CONTENT_LEAK
true
EOF
chmod +x "$work/session.sh"

export PATH="$work/fakebin:$JIT_BIN:$PATH"
export JIT_SESSION_NAME=k8s
export JIT_SECRETS="k8s:fake-k8s-item bao:fake-bao-item"
export JIT_WRAPPERS="kubectl:$work/realbin/kubectl kubectx:$work/realbin/kubectx kubens:$work/realbin/kubens k9s:$work/realbin/k9s bao:$work/realbin/bao"
export JIT_BINDINGS="kubectl:KUBECONFIG=k8s kubectx:KUBECONFIG=k8s kubens:KUBECONFIG=k8s k9s:KUBECONFIG=k8s bao:BAO_TOKEN=+bao"
export JIT_REQUIRED_ENV="BAO_ADDR"
export BAO_ADDR="https://bao.internal:8200"
export BAO_TEST_ENV_OUT="$work/bao-env.txt"
export JIT_BROKER="$JIT_BIN/jit-auth-broker"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Baselines: other interactive auth sessions may legitimately be running;
# only fail if THIS run leaks (dirs or brokers above baseline).
before="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"
# broker liveness: delta of brokers serving k8s sockets
before_brokers="$(pgrep -f "jit-auth-broker serve --socket $XDG_RUNTIME_DIR/jit-auth-k8s-" | wc -l || true)"
before_brokers=$(echo "$before_brokers" | head -1)
out="$(SHELL="$work/session.sh" jit-auth-run 2>&1)" || fail_test "jit-auth-run exited nonzero: $out"

# 1. wrapper ran and served content (both slots)
echo "$out" | grep -q "ran:get" || fail_test "wrapped tools did not run"
echo "$out" | grep -q "bao:token-ok addr=https://bao.internal:8200" || fail_test "bao literal token injection failed: $out"
pass "bao receives literal BAO_TOKEN + static BAO_ADDR through its wrapper"

# 2. mutation persistence through the shared memfd
echo "$out" | grep -q MUTATION_LOST && fail_test "context mutation did not persist across invocations"
ctx_two="$(echo "$out" | grep -c 'ctx=two')"
[ "$ctx_two" -ge 3 ] || fail_test "expected >=3 ctx=two readings after mutation, got $ctx_two"
pass "kubectx/kubens-style mutations persist across separate invocations (shared memfd)"
# 3. all wrapper names resolved
for t in kubectl kubectx kubens k9s; do
  echo "$out" | grep -q "ran:" || fail_test "$t wrapper did not execute"
done
echo "$out" | grep -c "bao:token-ok" | grep -q '^2$' || fail_test "bao wrapper did not run from plain + bash -c"
pass "kubectl, kubectx, kubens, k9s, bao all resolve through session wrappers"
# 4. bash/sh children + concurrency
echo "$out" | grep -q MUTATION_NOT_SHARED && fail_test "mutation not shared"
pass "plain/bash/sh children and concurrent invocations work"

fetches="$(wc -l < "$work/fetch.log" || true)"
[ "$fetches" -eq 2 ] || fail_test "configs fetched $fetches times, expected 2 (one per slot)"
[ "$(sort -u "$work/fetch.log" | wc -l)" -eq 2 ] || fail_test "same item fetched more than once"
pass "each slot's item fetched exactly once per session (combo: 2 items, 1 unlock)"

# 5. environment hygiene
grep -q "BW_SESSION_LEAK" "$work/child-env.txt" && fail_test "BW_SESSION leaked"
grep -q "KUBECONFIG_RAW_LEAK" "$work/child-env.txt" && fail_test "KUBECONFIG_RAW leaked"
grep -q "GLOBAL_KUBECONFIG_LEAK" "$work/child-env.txt" && fail_test "KUBECONFIG globally exported"
grep -q "BAO_TOKEN_LEAK" "$work/child-env.txt" && fail_test "BAO_TOKEN leaked into session shell env"
grep -q "ENV_CONTENT_LEAK" "$work/child-env.txt" && fail_test "config content leaked into env"
grep -q '^BAO_TOKEN=' "$work/bao-env.txt" || fail_test "BAO_TOKEN missing from wrapped process env"
grep -q '^BW_SESSION=' "$work/bao-env.txt" && fail_test "BW_SESSION leaked into wrapped process env"
pass "no BW_SESSION / KUBECONFIG_RAW / global KUBECONFIG / BAO_TOKEN in shell env; token only in the wrapped process"

# 6. no named config anywhere under the session runtime tree
session_dirs="$(find "$XDG_RUNTIME_DIR" -maxdepth 3 -type d -name 'jit-auth-k8s-*' -newer "$work" 2>/dev/null || true)"
for d in $session_dirs; do
  if find "$d" -maxdepth 2 -type f \( -name 'config' -o -name '*.conf' -o -name '*.yaml' -o -name '*token*' \) | grep -q .; then
    fail_test "named config/token file found in session dir: $d"
  fi
done
# broad belt+braces: no file anywhere in XDG_RUNTIME_DIR contains a fake secret
if grep -rl 'context: one' "$XDG_RUNTIME_DIR" >/dev/null 2>&1; then
  fail_test "a named file in XDG_RUNTIME_DIR contains the config"
fi
if grep -rl 'fake-bao-token' "$XDG_RUNTIME_DIR" >/dev/null 2>&1; then
  fail_test "a named file in XDG_RUNTIME_DIR contains the bao token"
fi
pass "no named config/token file exists during or after the session (memfd-only)"

# 7. cleanup: only this run's session dir must be gone (other interactive
# sessions may legitimately still be open)
after="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"
[ "$after" -le "$before" ] || fail_test "session runtime dirs left behind (before=$before after=$after)"
pass "session dir + sockets removed after exit"
# broker liveness: match only brokers whose socket lives under this run's
# runtime tree (other sessions' brokers are legitimate)
leftover_brokers="$(pgrep -f "jit-auth-broker serve --socket $XDG_RUNTIME_DIR/jit-auth-k8s-" | wc -l || true)"
[ "$leftover_brokers" -le "$before_brokers" ] || fail_test "$leftover_brokers jit-auth broker(s) still running (baseline $before_brokers)"
pass "brokers gone after exit (their memfds died with them)"

# 8. dynamic composer: auth bao k8s — two apps, one session, one unlock.
# Fragments embed REAL store binaries, so this session runs real kubectl/bao
# through the wrappers; the fake-tool mechanics are covered by part 1.
cat > "$work/session-combo.sh" <<'EOF'
kp="$(command -v kubectl || true)"
bp="$(command -v bao || true)"
case "$kp" in *jit-auth-bao-k8s*) ;; *) echo "KUBECTL_NOT_WRAPPED:$kp" ;; esac
case "$bp" in *jit-auth-bao-k8s*) ;; *) echo "BAO_NOT_WRAPPED:$bp" ;; esac
bao version | grep -q 'Bao v' || echo BAO_VERSION_FAILED
true
EOF
chmod +x "$work/session-combo.sh"
fetches_before="$(wc -l < "$work/fetch.log")"
out2="$(PATH="$work/fakebin:$JIT_BIN:$PATH" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" SHELL="$work/session-combo.sh" "$JIT_BIN/auth" bao k8s 2>&1)" || fail_test "auth bao k8s failed: $out2"
echo "$out2" | grep -q KUBECTL_NOT_WRAPPED && fail_test "auth combo: kubectl not wrapped: $out2"
echo "$out2" | grep -q BAO_NOT_WRAPPED && fail_test "auth combo: bao not wrapped: $out2"
echo "$out2" | grep -q BAO_VERSION_FAILED && fail_test "auth combo: real bao failed through wrapper"
delta=$(( $(wc -l < "$work/fetch.log") - fetches_before ))
[ "$delta" -eq 2 ] || fail_test "auth combo fetched $delta items, expected 2"
pass "auth bao k8s composes both apps into one session (wrappers resolved, real bao versioned, 2 fetches)"

combo_dirs="$(find "$XDG_RUNTIME_DIR" -maxdepth 3 -type d -name 'jit-auth-bao-k8s-*' -newer "$work" 2>/dev/null || true)"
[ -z "$combo_dirs" ] || fail_test "combo session runtime dirs left behind: $combo_dirs"
if grep -rl 'fake-bao-token' "$XDG_RUNTIME_DIR" >/dev/null 2>&1; then
  fail_test "a named file in XDG_RUNTIME_DIR contains the bao token (combo run)"
fi
pass "combo session cleanup: dirs gone, token never in a named file"

# 9. unknown app rejected with a helpful list
out_bogus="$($JIT_BIN/auth bogus-not-an-app 2>&1 || true)"
if echo "$out_bogus" | grep -q "unknown jit-auth app" && echo "$out_bogus" | grep -q "bao"; then
  pass "auth rejects unknown apps (with available-app list)"
else
  fail_test "auth did not reject an unknown app: $out_bogus"
fi

# 10. single-app alias shortcut (k8s-auth == auth k8s)
cat > "$work/session-single.sh" <<'EOF'
kp="$(command -v kubectl || true)"
case "$kp" in *jit-auth-k8s*) ;; *) echo "KUBECTL_NOT_WRAPPED:$kp" ;; esac
true
EOF
chmod +x "$work/session-single.sh"
out3="$(PATH="$work/fakebin:$JIT_BIN:$PATH" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" SHELL="$work/session-single.sh" "$JIT_BIN/k8s-auth" 2>&1)" || fail_test "k8s-auth alias failed: $out3"
echo "$out3" | grep -q KUBECTL_NOT_WRAPPED && fail_test "k8s-auth alias: kubectl not wrapped: $out3"
pass "single-app alias k8s-auth works (kubectl wrapped, real binary)"

echo "ALL TESTS PASSED"
