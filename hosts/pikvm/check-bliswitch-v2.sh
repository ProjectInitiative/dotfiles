#!/usr/bin/env bash
set -u

echo "== Stable BliSwitch device =="
if [[ -e /dev/bliswitch ]]; then
    ls -l /dev/bliswitch
    echo "resolves to: $(readlink -f /dev/bliswitch)"
    udevadm info -q property -n /dev/bliswitch | grep -E '^(ID_VENDOR_ID|ID_MODEL_ID|ID_MODEL|ID_REVISION)=' || true
else
    echo "/dev/bliswitch NOT FOUND"
fi

echo
echo "== Serial devices =="
ls -l /dev/serial/by-id/ 2>/dev/null || true
ls -l /dev/ttyUSB* 2>/dev/null || echo "No /dev/ttyUSB* devices found"

echo
echo "== BliSwitch udev rule =="
if [[ -f /etc/udev/rules.d/99-bliswitch-v2.rules ]]; then
    cat /etc/udev/rules.d/99-bliswitch-v2.rules
else
    echo "NOT INSTALLED"
fi

echo
echo "== xh_hk4401 installed path =="
python3 - <<'PY'
import importlib.util
spec = importlib.util.find_spec('kvmd.plugins.ugpio.xh_hk4401')
print(spec.origin if spec and spec.origin else 'NOT FOUND')
PY

echo
echo "== Patch state =="
DRIVER="$(python3 - <<'PY'
import importlib.util
spec = importlib.util.find_spec('kvmd.plugins.ugpio.xh_hk4401')
print(spec.origin if spec and spec.origin else '')
PY
)"
if [[ -n "$DRIVER" && -f "$DRIVER" ]]; then
    grep -nE 'max=7|max = 7|\[1-8\]|assert 0 <= channel <= 7' "$DRIVER" || true
fi

echo
echo "== kvmd service =="
systemctl --no-pager --full status kvmd 2>/dev/null | head -n 20 || true
