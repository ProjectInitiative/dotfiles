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

- Account used: the non-admin **`pikvm` user** (digest auth). Password lives
  in `/etc/kvmd/dli-epcr6.env` (`DLI_PASS=...`, root:kvmd 0600, loaded via
  systemd drop-in) — never in the repo. At NixOS-conversion time it moves
  to sops (`dli_epcr6_password`, wired in the NixOS module).
- DLI **client access tokens (bearer) are NOT supported** on the EPCR6 —
  the wired-only firmware routes client/bearer auth through the user
  login path (`login denied ... (digest): no such user`) regardless of
  the "Allow plaintext URL logins" setting. A fully-registered client
  (`pikvmcmd`, hash-bound, scoped, token record minted) still 401s.
  The client object is left on the unit as a firmware-update lottery
  ticket; do not build on it.
- Required unit settings (all done): Users → grant `pikvm` outlets 5-8;
  External APIs → "Allow REST-style API" + "Allow REST-style API for
  non-admin users" (the latter was the missing 403 gate).
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

## Auth saga (read before "simplifying")

For the record, the paths that DON'T work on this unit, all verified:
1. Legacy `outlet?N=ON|OFF|CCL` — endpoint doesn't exist on "Power
   Controller" firmware; silently no-ops with a 200 redirect page.
2. REST as admin-only-by-default — fixed by "Allow REST-style API for
   non-admin users".
3. Basic/plaintext auth — explicitly denied by the unit.
4. Bearer client tokens — unsupported (see above); ~2h of schema
   archaeology confirms the tables exist but the HTTP layer ignores them.
5. `secret_hash` is insert-time-only via REST (update returns 500 "not
   permitted"); creation must be a PUT to the element URL with the FULL
   field set (`refresh_tokens`/`access_tokens` included) — POST is 405.
The working design is deliberately boring: digest + non-admin user +
scoped outlet grants.

## Outlet map — VERIFIED 2026-11-23

Verified by Kyle against the physical plugs. Note the DLI outlet numbering
differs from the BliSwitch channel numbering:

- DLI outlet 8 = Astrolabe (BliSwitch ch3 / "GPIO4")
- DLI outlet 6 = Chronometer (BliSwitch ch4 / "GPIO5")
- DLI outlet 7 = Sextant (BliSwitch ch5 / "GPIO6")
- DLI outlet 5 = Octant (BliSwitch ch6 / "GPIO7")

Outlets 1-4 are unassigned.

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
