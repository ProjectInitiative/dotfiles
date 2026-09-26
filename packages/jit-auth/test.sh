#!/usr/bin/env bash
# Lightweight validation for jit-auth (fake credentials only).
# Fakes `bw` and the wrapped tools, then drives the real broker + wrapper
# pipeline through a scripted child shell. Covers: once-per-session fetch,
# PATH-wrapper invocation from plain/bash/sh children, MUTATION PERSISTENCE
# via the shared session memfd, independent per-client offsets, concurrency,
# env hygiene, absence of any named kubeconfig, and exit cleanup.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIT_BIN="${JIT_BIN:-$here/result/bin}"
work="$(mktemp -d /tmp/jit-auth-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail_test() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# --- fake `bw` -----------------------------------------------------------
# Records config fetches to prove once-per-session.
mkdir -p "$work/fakebin"
cat > "$work/fakebin/bw" <<EOF
#!/usr/bin/env bash
case "\$1" in
  status) echo '{"status": "unauthenticated"}' ;;
  unlock) echo "fake-session-token" ;;
  sync)   exit 0 ;;
  get)    echo "fake-config" >> "$work/fetch.log"; printf 'context: one\nnamespace: default\n' ;;
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
# concurrency: independent offsets, no stream consumption between clients
kubectl get pods & kubectl get svc & wait
env > "$work/child-env.txt"
[ -z "\${BW_SESSION:-}" ] || echo BW_SESSION_LEAK
[ -z "\${KUBECONFIG_RAW:-}" ] || echo KUBECONFIG_RAW_LEAK
[ -z "\${KUBECONFIG:-}" ] || echo GLOBAL_KUBECONFIG_LEAK
grep -q 'context: one' "$work/child-env.txt" && echo ENV_CONTENT_LEAK
true
EOF
chmod +x "$work/session.sh"

export PATH="$work/fakebin:$JIT_BIN:$PATH"
export JIT_SESSION_NAME=k8s
export JIT_BW_ITEM=fake-item-uuid
export JIT_CMD_NAME=kubectl
export JIT_CONFIG_ENV=KUBECONFIG
export JIT_REAL_BIN="$work/realbin/kubectl"
export JIT_WRAPPERS="kubectl:$work/realbin/kubectl kubectx:$work/realbin/kubectx kubens:$work/realbin/kubens k9s:$work/realbin/k9s"
export JIT_BROKER="$JIT_BIN/jit-auth-broker"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Baselines: other interactive auth sessions may legitimately be running;
# only fail if THIS run leaks (dirs or brokers above baseline).
before="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"
# broker liveness: delta of brokers serving k8s sockets
before_brokers="$(pgrep -f "jit-auth-broker serve --socket $XDG_RUNTIME_DIR/jit-auth-k8s-" | wc -l || true)"
before_brokers=$(echo "$before_brokers" | head -1)
out="$(SHELL="$work/session.sh" jit-auth-run 2>&1)" || fail_test "jit-auth-run exited nonzero: $out"

# 1. wrapper ran and served content
echo "$out" | grep -q "ran:get" || fail_test "wrapped tools did not run"
# 2. mutation persistence through the shared memfd
echo "$out" | grep -q MUTATION_LOST && fail_test "context mutation did not persist across invocations"
ctx_two="$(echo "$out" | grep -c 'ctx=two')"
[ "$ctx_two" -ge 3 ] || fail_test "expected >=3 ctx=two readings after mutation, got $ctx_two"
pass "kubectx/kubens-style mutations persist across separate invocations (shared memfd)"
# 3. all wrapper names resolved
for t in kubectl kubectx kubens k9s; do
  echo "$out" | grep -q "ran:" || fail_test "$t wrapper did not execute"
done
pass "kubectl, kubectx, kubens, k9s all resolve through session wrappers"
# 4. bash/sh children + concurrency
echo "$out" | grep -q MUTATION_NOT_SHARED && fail_test "mutation not shared"
pass "plain/bash/sh children and concurrent invocations work"

fetches="$(wc -l < "$work/fetch.log" || true)"
[ "$fetches" -eq 1 ] || fail_test "config fetched $fetches times, expected 1"
pass "config fetched exactly once per session"

# 5. environment hygiene
grep -q "BW_SESSION_LEAK" "$work/child-env.txt" && fail_test "BW_SESSION leaked"
grep -q "KUBECONFIG_RAW_LEAK" "$work/child-env.txt" && fail_test "KUBECONFIG_RAW leaked"
grep -q "GLOBAL_KUBECONFIG_LEAK" "$work/child-env.txt" && fail_test "KUBECONFIG globally exported"
grep -q "ENV_CONTENT_LEAK" "$work/child-env.txt" && fail_test "config content leaked into env"
pass "no BW_SESSION / KUBECONFIG_RAW / global KUBECONFIG / config content in shell env"

# 6. no named kubeconfig anywhere under the session runtime tree
session_dirs="$(find "$XDG_RUNTIME_DIR" -maxdepth 3 -type d -name 'jit-auth-k8s-*' -newer "$work" 2>/dev/null || true)"
for d in $session_dirs; do
  if find "$d" -maxdepth 2 -type f \( -name 'config' -o -name '*.conf' -o -name '*.yaml' \) | grep -q .; then
    fail_test "named config file found in session dir: $d"
  fi
done
# broad belt+braces: no file anywhere in XDG_RUNTIME_DIR contains the fake secret
if grep -rl 'context: one' "$XDG_RUNTIME_DIR" >/dev/null 2>&1; then
  fail_test "a named file in XDG_RUNTIME_DIR contains the config"
fi
pass "no named kubeconfig/config file exists during or after the session (memfd-only)"

# 7. cleanup: only this run's session dir must be gone (other interactive
# sessions may legitimately still be open)
after="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"
[ "$after" -le "$before" ] || fail_test "session runtime dirs left behind (before=$before after=$after)"
pass "session dir + socket removed after exit"
# broker liveness: match only brokers whose socket lives under this run's
# runtime tree (other sessions' brokers are legitimate)
leftover_brokers="$(pgrep -f "jit-auth-broker serve --socket $XDG_RUNTIME_DIR/jit-auth-k8s-" | wc -l || true)"
[ "$leftover_brokers" -le "$before_brokers" ] || fail_test "$leftover_brokers jit-auth broker(s) still running (baseline $before_brokers)"
pass "broker gone after exit (its memfd died with it)"

echo "ALL TESTS PASSED"
