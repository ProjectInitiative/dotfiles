#!/bin/bash

echo "=== Driver Status ==="
lsmod | grep rocket || echo "Rocket driver module not loaded."
echo ""

echo "=== Device Tree Node Status ==="
for node in /sys/firmware/devicetree/base/npu@fdab0000 /sys/firmware/devicetree/base/npu@fdac0000 /sys/firmware/devicetree/base/npu@fdad0000; do
    if [ -d "$node" ]; then
        echo "Node: $node"
        echo -n "  Status: " && cat "$node/status" 2>/dev/null && echo "" || echo "N/A"
        echo "  Properties:"
        ls "$node" | grep -E "supply|compatible"
        echo "  npu-supply: $(hexdump -C "$node/npu-supply" 2>/dev/null | head -n 1 || echo "Not found")"
    else
        echo "Node $node not found."
    fi
    echo "---"
done

echo ""
echo "=== Regulator Check ==="
ls -d /sys/class/regulator/regulator* | while read r; do
    NAME=$(cat "$r/name" 2>/dev/null)
    if [[ "$NAME" == *"npu"* ]]; then
        echo "Found: $NAME at $r"
        echo "  Status: $(cat "$r/state" 2>/dev/null)"
    fi
done

echo ""
echo "=== Kernel Messages ==="
sudo dmesg | grep -iE "rocket|rknn|npu|accel|deferred" | tail -n 30
