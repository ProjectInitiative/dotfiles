#!/usr/bin/env bash
# Lightweight validation for jit-auth (fake credentials only).
# Exercises the broker + wrapper lifecycle without Bitwarden by faking `bw`
# on PATH and calling jit-auth-run with JIT_* parameters directly.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIT_BIN="${JIT_BIN:-$here/result/bin}"
work="$(mktemp -d /tmp/jit-auth-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail_test() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# --- fake `bw` -----------------------------------------------------------
# Records how many times the config was fetched to prove once-per-session.
mkdir -p "$work/fakebin"
cat > "$work/fakebin/bw" <<EOF
#!/usr/bin/env bash
case "\$1" in
  status) echo '{"status": "unauthenticated"}' ;;
  unlock) echo "fake-session-token" ;;
  sync)   exit 0 ;;
  get)    echo "fake-kubeconfig-line-1" >> "$work/fetch.log"; echo "fake-kubeconfig-content" ;;
  *)      exit 1 ;;
esac
EOF
chmod +x "$work/fakebin/bw"

# --- fake real binary ----------------------------------------------------
mkdir -p "$work/realbin"
cat > "$work/realbin/kubectl" <<'EOF'
#!/usr/bin/env bash
conf="${KUBECONFIG:?KUBECONFIG not set by jit-auth client}"
echo "kubectl-ran conf=$conf"
[ -r "$conf" ] || { echo "config unreadable" >&2; exit 1; }
head -c 100 "$conf" > /dev/null || { echo "config empty" >&2; exit 1; }
echo "config-contents-ok"
EOF
chmod +x "$work/realbin/kubectl"

# --- run the auth core with a scripted child shell -----------------------
cat > "$work/session.sh" <<EOF
#!/usr/bin/env bash
kubectl get pods
bash -c 'kubectl get pods'
sh -c 'kubectl get pods'
kubectl get pods & kubectl get svc & wait
env > "$work/child-env.txt"
test -z "\${BW_SESSION:-}" || echo "BW_SESSION_LEAK"
test -z "\${KUBECONFIG_RAW:-}" || echo "KUBECONFIG_RAW_LEAK"
echo "$work" > /dev/null  # keep shellvar happy
EOF
chmod +x "$work/session.sh"

export PATH="$work/fakebin:$JIT_BIN:$PATH"
export JIT_SESSION_NAME=k8s
export JIT_BW_ITEM=fake-item-uuid
export JIT_CMD_NAME=kubectl
export JIT_CONFIG_ENV=KUBECONFIG
export JIT_REAL_BIN="$work/realbin/kubectl"
export JIT_BROKER="$JIT_BIN/jit-auth-broker"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Non-interactive child shell for testing
SHELL_OUT="$(SHELL="$work/session.sh" jit-auth-run 2>&1)" || fail_test "jit-auth-run exited nonzero: $SHELL_OUT"

echo "$SHELL_OUT" | grep -q "kubectl-ran" || fail_test "kubectl wrapper did not run"
echo "$SHELL_OUT" | grep -q "config-contents-ok" || fail_test "config not readable via memfd"
echo "$SHELL_OUT" | grep -q "session terminated" || fail_test "termination message missing"

fetches="$(wc -l < "$work/fetch.log")"
[ "$fetches" -eq 1 ] || fail_test "config fetched $fetches times, expected 1 (once per session)"
pass "config fetched exactly once per session"

concurrent_count="$(echo "$SHELL_OUT" | grep -c "config-contents-ok")"
[ "$concurrent_count" -ge 4 ] || fail_test "expected >=4 successful invocations (direct/bash/sh/concurrent), got $concurrent_count"
pass "wrapper works from direct, bash -c, sh -c, and concurrent invocations"

grep -q "BW_SESSION_LEAK" "$work/child-env.txt" && fail_test "BW_SESSION leaked into auth shell env"
grep -q "KUBECONFIG_RAW_LEAK" "$work/child-env.txt" && fail_test "KUBECONFIG_RAW leaked into auth shell env"
grep -q "fake-kubeconfig-content" "$work/child-env.txt" && fail_test "raw config content leaked into env"
pass "no BW_SESSION / KUBECONFIG_RAW / config content in environment"

# --- cleanup verification -------------------------------------------------
leftovers="$(ls -d "$XDG_RUNTIME_DIR"/jit-auth-k8s-* 2>/dev/null | wc -l || true)"
[ "$leftovers" -eq 0 ] || fail_test "session runtime dirs left behind: $leftovers"
pass "session runtime directories removed after exit"

brokers="$(pgrep -f 'jit-auth-broker serve' | wc -l || true)"
[ "$brokers" -eq 0 ] || fail_test "broker processes left running: $brokers"
pass "no broker processes survive exit"

echo "ALL TESTS PASSED"
