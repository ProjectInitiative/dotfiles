# kvmd 8-port driver patch — BliSwitch v2

## The problem

kvmd's `xh_hk4401` GPIO driver is written for **4-channel** switches
(channel validator `max=3`, status regex `[1-4]`, transmit assert `<= 3`).
The BliSwitch v2 exposes **8 channels** (status replies `G01gA`–`G08gA`,
selections 1-8), so without a patch only inputs 1-4 work.

## The patch

`patch-xh_hk4401-8port.py` makes three minimal, idempotent changes to the
**installed** driver (supports both modern `valid_number.mk(...)` and older
`functools.partial(...)` layouts, refuses unexpected code):

1. channel validator: `max=3` → `max=7`
2. receive regex: `[1-4]` → `[1-8]` (both protocol 1 and 2)
3. transmit assert: `0 <= channel <= 3` → `0 <= channel <= 7`

Reference copies in this directory:
- `xh_hk4401.py.upstream-4.215` — pristine kvmd 4.215 driver (pre-patch),
  taken from the device before patching; useful for diffing when kvmd
  updates land.
- `patch-xh_hk4401-8port.py` — the patcher itself (from the device's
  `~/bliswitch/` bundle).
- `check-bliswitch-v2.sh` — serial/driver/service diagnostics.

## CRITICAL: kvmd updates wipe this patch

PiKVM OS package updates (`pacman -Syu`) replace
`/usr/lib/python3.14/site-packages/kvmd/plugins/ugpio/xh_hk4401.py`,
silently reverting to 4-port behavior. **Symptom: BliSwitch inputs 5-8
stop working after an update.** Re-apply with:

```sh
scp hosts/pikvm/patch-xh_hk4401-8port.py pikvm:/tmp/
ssh pikvm "rw && DRIVER=\$(python3 -c \"import importlib.util; print(importlib.util.find_spec('kvmd.plugins.ugpio.xh_hk4401').origin)\") && cp -a \$DRIVER \$DRIVER.bliswitch-v2-backup.\$(date +%Y%m%d-%H%M%S) && python3 /tmp/patch-xh_hk4401-8port.py \$DRIVER && python3 -m py_compile \$DRIVER && systemctl restart kvmd && ro"
```

The patcher is idempotent: it reports "Already patched" if re-run.

## On NixOS (future)

The same patch must be applied to the nix-store kvmd package — either
`overrideAttrs` with a `postPatch`/`postFixup` running this script against
`$out/.../kvmd/plugins/ugpio/xh_hk4401.py`, or a kvmd fork PR upstream.
The module (`modules/nixos/services/pikvm-kvmd`) documents the hook point;
on PiKVM OS this remains a post-update maintenance step (see above).
