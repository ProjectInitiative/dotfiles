#!/usr/bin/env bash
# Lightweight validation for jit-auth (fake credentials only).
# Fakes `bw` on PATH and a fake `kubectl`, then drives jit-auth-run through a
# scripted child shell to verify: once-per-session retrieval, KUBECONFIG
# propagation to plain/bash/sh children, context-mutation persistence,
# concurrency, env hygiene, and exit cleanup.
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
  get)    echo "fake-config" >> "$work/fetch.log"; printf 'apiVersion: v1\nkind: Config\n' ;;
  *)      exit 1 ;;
esac
EOF
chmod +x "$work/fakebin/bw"

# --- fake kubectl --------------------------------------------------------
# Verifies it received KUBECONFIG, can read it, and can MUTATE it (like
# kubectx does). Mutation persistence is the key regression check for the
# named-file design.
mkdir -p "$work/realbin"
cat > "$work/realbin/kubectl" <<EOF
#!/usr/bin/env bash
conf="\${KUBECONFIG:?KUBECONFIG not set}"
[ -r "\$conf" ] || { echo "config unreadable" >&2; exit 1; }
grep -q 'apiVersion: v1' "\$conf" || { echo "config wrong content" >&2; exit 1; }
echo "ran:\$1 conf=\$conf"
# On 'use-context mc', mutate the file like kubectx would.
if [ "\$1" = "use-context" ]; then
  printf 'apiVersion: v1\nkind: Config\ncurrent-context: mc\n' > "\$conf"
fi
EOF
chmod +x "$work/realbin/kubectl"

# --- scripted auth session ----------------------------------------------
cat > "$work/session.sh" <<EOF
#!/usr/bin/env bash
# plain PATH-resolved invocation
kubectl get pods
# children without any knowledge of this system
bash -c 'kubectl get ns'
sh -c 'kubectl get pods'
# mutation via a kubectx-like call, then verify persistence in a separate child
kubectl use-context mc
grep -q 'current-context: mc' "\$KUBECONFIG" || { echo MUTATION_LOST; exit 1; }
bash -c 'grep -q "current-context: mc" "\$KUBECONFIG"' || { echo MUTATION_NOT_SHARED; exit 1; }
kubectl get pods
# concurrency
kubectl get pods & kubectl get svc & wait
env > "$work/child-env.txt"
[ -z "\${BW_SESSION:-}" ] || echo BW_SESSION_LEAK
[ -z "\${KUBECONFIG_RAW:-}" ] || echo KUBECONFIG_RAW_LEAK
grep -q 'fake-config' "$work/child-env.txt" && echo ENV_CONTENT_LEAK
true
EOF
chmod +x "$work/session.sh"

# realbin on PATH: the session resolves kubectl via normal PATH lookup
export PATH="$work/fakebin:$work/realbin:$JIT_BIN:$PATH"
export JIT_SESSION_NAME=k8s
export JIT_BW_ITEM=fake-item-uuid
export JIT_CMD_NAME=kubectl
export JIT_CONFIG_ENV=KUBECONFIG
export JIT_REAL_BIN="$work/realbin/kubectl"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Baseline: other auth sessions (e.g. an interactive one) may legitimately be
# running; only fail if THIS run leaks a new directory.
before="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"

out="$(SHELL="$work/session.sh" jit-auth-run 2>&1)" || fail_test "jit-auth-run exited nonzero: $out"

echo "$out" | grep -q "ran:get" || fail_test "kubectl wrapper did not run"
mutation_ok="$(echo "$out" | grep -c 'ran:get')"
[ "$mutation_ok" -ge 4 ] || fail_test "expected >=4 successful invocations, got $mutation_ok"
echo "$out" | grep -q MUTATION_LOST && fail_test "context mutation did not persist in session file"
echo "$out" | grep -q MUTATION_NOT_SHARED && fail_test "mutation not visible to a separate child process"
pass "KUBECONFIG file works for plain/bash/sh children, persists mutations, concurrent-safe"

fetches="$(wc -l < "$work/fetch.log" || true)"
[ "$fetches" -eq 1 ] || fail_test "config fetched $fetches times, expected 1"
pass "config fetched exactly once per session"

grep -q "BW_SESSION_LEAK" "$work/child-env.txt" && fail_test "BW_SESSION leaked"
grep -q "KUBECONFIG_RAW_LEAK" "$work/child-env.txt" && fail_test "KUBECONFIG_RAW leaked"
grep -q "ENV_CONTENT_LEAK" "$work/child-env.txt" && fail_test "config content leaked into env"
pass "no BW_SESSION / KUBECONFIG_RAW / config content in environment"

# --- cleanup verification ------------------------------------------------
after="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"
[ "$after" -le "$before" ] || fail_test "session runtime dirs left behind (before=$before after=$after)"
[ -f "$XDG_RUNTIME_DIR"/jit-auth-k8s-*/config ] 2>/dev/null && fail_test "config file survived exit"
pass "session dir + config file removed after exit"

echo "ALL TESTS PASSED"
