# PiKVM node → NixOS — SSH discovery (2026-10-06)

Source: live SSH session to `root@pikvm` (Arch Linux ARM, tailnet 100.117.169.9,
mgmnt 172.16.1.85). Raw artifacts in `docs/pikvm/artifacts/`.
Context: keel `OQ-0020-pikvm-nixos-conversion`.

## Hardware & software

| item | value |
|---|---|
| board | Raspberry Pi 4 Model B Rev 1.1 |
| OS | Arch Linux ARM |
| kvmd | 4.215-1 |
| platform | kvmd-platform-v3-hdmi-rpi4 → `hardwareVersion = "v3-hdmi-rpi4"` |
| ustreamer | 6.66-1 |
| janus | janus-gateway-pikvm 1.4.2-2 |
| extras | kvmd-fan 0.33, kvmd-webterm 0.52 |

## ⚠️ Key finding: the "8-host kvmd patches" are pure configuration

`pacman -Qkk kvmd` reports 8 altered files — all of them are **just**
`/etc/kvmd/htpasswd` + `/etc/kvmd/override.yaml` (mtime/size/hash mismatch
because the BliSwitch installer rewrote them). **No kvmd source files are
modified.** The 8-host BliSwitch v2 switching works entirely through:

1. kvmd's **stock `xh_hk4401` GPIO driver** driven by `override.yaml`
   (driver `hk`, `protocol: 1`, device `/dev/bliswitch`, 8 channels × led/button,
   `view.table` menu: Capstan1, Capstan2, Capstan3, Astrolabe, Chronometer,
   Sextant, Octant, INPUT 8).
2. A udev rule producing the stable `/dev/bliswitch` symlink (CH340, rev 0254).

→ This **disproves** the OQ-0020 assumption that kvmd needs an overlay/fork with
the owner's patches. A `services.kvmd.settings` override + udev rules is
sufficient. No source patching, no janus patching observed on this box.

## Enabled kvmd services (live)

kvmd, kvmd-fan, kvmd-janus, kvmd-media, kvmd-nginx, kvmd-oled (+reboot/shutdown),
kvmd-otg, kvmd-pm, kvmd-pst, kvmd-watchdog, kvmd-webterm, kvmd-bootconfig.
(kvmd.service: `User=kvmd`, `ExecStart=/usr/bin/kvmd --run`)

## Network

- `eth0` static `172.16.1.85/24` (mgmnt), default via `172.16.1.1`
- `eth0.2` VLAN 2, DHCP → `192.168.1.220/24` (gateway 192.168.1.254)
- `tailscale0` `100.117.169.9` (tagged device `pikvm`)

## Storage

- `/var/lib/kvmd/msd` + `/var/lib/kvmd/pst` on `/dev/mmcblk0p3` (5.9G root)
- NixOS: start on root fs, consider a dedicated partition later.

## udev rules (ported verbatim)

- `1-e52c-kvm.rules`: `KERNELS=="1-1.2.1"` → `/dev/e52c`
- `10-ezcoo-kvm.rules`: `KERNELS=="1-1.4"` → `/dev/ezcoo` (CH340; pikvm-atx serial path)
- `11-pikvm-atx-kvm.rules`: idVendor/idProduct `0232:0232` → `/dev/pikvmatx`
  (the RP2040 ATX firmware — related: keel `pikvm-atx`)
- `99-bliswitch-v2.rules`: CH340 `ID_REVISION 0254` → `/dev/bliswitch`
- `raspberrypi.rules`: vchiq/input 0777 (upstream default, nixos-hardware covers)

⚠️ The `KERNELS=="1-1.2.1"` / `1-1.4` paths assume the same physical USB hub
topology (VIA Labs hub on Bus 1). Same Pi + same cabling → same paths.

## USB inventory

VIA Labs hub (2109:3431/2817/0817), 2× CH340 (bliswitch + ezcoo), FT232,
ASIX AX88179 gigabit on USB3.

## Packaging bases assessed (2026-10-06)

| base | kvmd | state | verdict |
|---|---|---|---|
| **hatch01/nixos-pikvm** | **4.217** (python314) | **active** (commit 2026-10-05) | ✅ chosen base — `services.kvmd` module w/ settings override, `hardwareVersion`, udev rules from kvmd configs, janus/ustreamer wiring, nginx, imports nixos-hardware `raspberry-pi-4`; flake-parts; x86_64+aarch64 |
| matthewcroughan/nixkvm `wip` | 4.2 (2024-07) | stale | ❌ as base — but the best reference for BliKVM specifics (own kernel build, disko, kvmd-otg/otgnet/ipmi/vnc/janus/watchdog modules, tc358743 edid) |
| ritiek/nixkvm | (RPi Zero 2W fork, pushed 2026-07) | niche | ❌ different target (Zero 2W) |
| pikvm/packages (PKGBUILDs) | 4.215+ | active | 📚 reference for dep lists |
| NixOS/nixpkgs#428203 | — | open, 9 comments | track only |

## Remaining TODOs before first deploy

1. sops secrets: kvmd htpasswd, tailscale auth key (tagged device re-auth).
2. Verify `xh_hk4401` driver behavior on kvmd 4.217 matches 4.215 config.
3. Decide install path: SD image build vs kexec/nixos-infect vs manual
   nixos-install (Arch must be taken down; it currently controls 8 hosts).
4. aarch64 build path: no remote builders; binfmt `extra-platforms` allows
   emulated aarch64 builds locally (slow) — see keel OQ-0019.
5. OLED (kvmd-oled), fan (kvmd-fan), watchdog services — verify hatch01 module
   exposes them or add systemd units.
