# PiKVM — BliSwitch v2 + Digital Loggers EPCR6

Config for the `pikvm` node (stock PiKVM OS / Arch, **not** NixOS yet —
see `modules/nixos/services/pikvm-kvmd/` for the future-conversion module).

## Files

| File | Purpose | Deployed to |
|---|---|---|
| `override.yaml.device` | The pre-EPCR6 base config (BliSwitch v2 8-port, `xh_hk4401` driver, `/dev/bliswitch` udev symlink) | — (reference) |
| `epcr6-gpio.yaml` | EPCR6 add-on block (cmd/cmdret drivers, scheme, view rows). Merge under the existing `kvmd:` key | merged into `/etc/kvmd/override.yaml` |
| `override.yaml.merged` | The merged result currently running on the device | `/etc/kvmd/override.yaml` |
| `dli-outlet` | Control script for the EPCR6 (legacy `outlet?N=ON\|OFF\|CCL` for control; REST-then-`/status`-bitmap for state) | `/etc/kvmd/bin/dli-outlet` (root:kvmd 0750) |

## Topology

- PiKVM: `172.16.1.85` (also tailscale `100.117.169.9`), ssh alias `pikvm`
- EPCR6: `172.16.1.4` (found by DLI MAC OUI `7C:E1:FF`)
- BliSwitch v2: channels 0-2 = Capstan1-3, 3-6 = Astrolabe/Chronometer/Sextant/Octant (DGX Spark nodes, no ATX), 7 = spare input

## EPCR6 account reality (as of 2026-11-23)

- Account used: `pikvm` (non-admin). Password is **not stored in this repo**
  — `dli-outlet` reads `DLI_PASS` from the environment; on-device it is
  provided to the kvmd service via `/etc/kvmd/dli-epcr6.env` (root:kvmd 0600,
  `DLI_PASS=...`), and at NixOS-conversion time via sops
  (`dli_epcr6_password`, wired in the NixOS module).
- Non-admin accounts **can toggle outlets** via legacy HTTP but **cannot read
  state**: `/restapi/...` → 403 "requires administrative rights", legacy
  `/status` bitmap comes back empty (no outlet visibility granted).
- Consequence: buttons work; status LEDs stay dark. Fix on the EPCR6 web UI:
  grant the `pikvm` user outlet visibility (Setup → Users), or use admin
  creds in the script. The script prefers REST and falls back to the legacy
  bitmap automatically, so no script change needed once visibility exists.
- EPCR6 settings that must stay enabled: Setup → External APIs →
  "Allow legacy plaintext login methods" (control) and "Allow REST-style
  API" (state).

## Outlet map — UNVERIFIED

`3=Astrolabe 4=Chronometer 5=Sextant 6=Octant` was assumed from BliSwitch
channel alignment, not verified against the physical plugs. Verify before
trusting an Off/Cycle press. Outlets 1-2 (Capstan1/2) and 7-8 are unassigned.

## Regenerating `override.yaml.merged`

The merged file is generated from `override.yaml.device` + `epcr6-gpio.yaml`
(nested dict merge on `kvmd.gpio`, view tables concatenated). After editing
either piece, rebuild, diff against the device, restart kvmd:

```sh
ssh pikvm "cat /etc/kvmd/override.yaml" > /tmp/on-device.yaml  # compare
scp hosts/pikvm/override.yaml.merged pikvm:/etc/kvmd/override.yaml
ssh pikvm "kvmd --run -m >/dev/null && systemctl restart kvmd"
```

Validate before deploying: `kvmd --run -m` on-device must show the new
`dli_*` channels; `systemctl is-active kvmd` after restart. On-device backup
of the pre-EPCR6 config: `/etc/kvmd/override.yaml.bak-20261123091658`.

## YAML gotcha

Unquoted `on`/`off`/`state` in cmd lists parse as **booleans** under YAML
1.1 (kvmd's parser) and break the driver config — always quote them
(`"on"`, `"off"`, `"state"`, `"cycle"`). The validator in the session that
built this caught exactly that.

## PiKVM OS editing workflow

The root FS is read-only by default: `rw` → edit → restart kvmd → `ro`.
If it won't remount RO, reboot rather than leaving it RW.
