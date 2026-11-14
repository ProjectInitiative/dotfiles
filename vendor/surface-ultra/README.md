# Surface Laptop Ultra — vendored sources

Vendored copies of the upstream patches, DKMS modules, and services for the
Microsoft Surface Laptop Ultra (NVIDIA RTX Spark N1X, `aarch64-linux`). These
are pinned copies so the NixOS derivations in this repo build reproducibly
from local source instead of unpinned GitHub HEADs.

Consumed by:
- `packages/surface-ultra/*` — package derivations
- `modules/nixos/hardware/surface-laptop-ultra/*` — NixOS module
- `systems/aarch64-linux/surface-ultra/` — host config

## Sources

### gist-teo-casares/
Raw files from https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8
("Omarchy on the Microsoft Surface Laptop Ultra (NVIDIA N1X): the whole
journey") — kernel patches, DKMS module sources, services, udev rules, UCM
profile, and the full write-up (`0-README.md`).

Fetched 2026-11-13, per-file SHA256s (from the gist API raw URLs at revision
`219814edf9563ba2e91f16bb0a75eea6f31cdbdb`):

```
d490dec7e4a58aa13b402501f4965f3feadaf211d56808d9723924fb6ab43d51  n1x_carveout_memmap.c
b9689e957ac3f864c299277c003ede33e8dfce9dc1da82e1dee73f82670f3988  n1x_carveout_memmap.Makefile
e1f87a25d6c20607934e15c5c0d9f8d2755f98620acba509d00683c8f83647b5  surface-n1x-ssam.patch
6083e33cc484e4b236ba7755bcb1262bbcdab7d6f422d1954a95ca1ad01301bb  surface-ultra-mach.patch
4311b45c17267f3ab6e1add543d418da06b127f0708c439c8d87d96cdbc94888  STAGED-8250_mtk-nvda0240-52mhz.patch
c73474195a8c0bdab57159311a0d93ec4af08fdf197ceaa321b6e609723594ac  sdw_pad_drive.c
f8026a26accd0cc70146e872ab8a067a0709d1994ae38d9df41180d73143f32f  nvidia-615.78.08-n1x-carveout.patch
d3e2c9341d38b2853e80354e4bea488fabb94f00126aa3831ed1920c2e78f1a9  HiFi-surface-laptop-ultra.conf
a6e9a0bc007bb8bce18af16a4eeff823e6eedcfdc95985f9e52f9c5788f9fcaa  MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf
541bd2277ebba13b2d3e222f9a5adfa4fa128c65ac64e3c73cc3fe8ef8bfe910  surface-laptop-ultra-touchpad.quirks
229794d303d1e43f56515a65e45b88d2eb560d7bc91256b6c7034963df0afeff  71-key-repeat-surface-kbd.rules
ae4106174efb9f1712ad8fd143fe5b4826df3e17ecb204694cb97cc9a0ced235  kbd-repeat-delay
153c71d38650402e57a28d3cdf4bb7cc90473b17a4b3a40f5b30c48638585aac  n1x-touchpad-ptp
199dfe5550d42e79024c4107f6834076fbd56611cc6a8f54e54b2ae1556c6b10  n1x-edp-backlight
9bcda0e5a04c02c89a02d9a6adf91cf3cb90ad9d45045554779175674a311d97  surface-kbd-backlight
6448dfeb2d739d054f89f25516f52aee50a251df2cfaf1dd653bc393baac9c69  n1x-sdw-settle
c5e235081ea4cfea52528cf3d057e0959554c5db8b7df87c2b009c713a2bd3fc  n1x-dkms-guard
```

(The .service/.conf files and 0-README.md are also present; hashes omitted
here for brevity but re-verify against the gist if in doubt.)

### surface-ultra-camera/
Clone of https://github.com/ikegam/surface-ultra-camera at commit
`e95a23202f3a1c260f4e61476d0b0d464ebfba56` (2026-11-10). MediaTek MT8991
camera ISP driver (seninf/camsys/CCU) making the OV02C10 front camera and
VD55G1 IR camera work as libcamera/PipeWire cameras. Requires the CCU
firmware `nvCCU.img`, which must be extracted from the machine's Windows
partition (`firmware/extract-from-windows.sh`) — NOT redistributable, so it
is not vendored here.

### surface-ultra-misc/
Clone of https://github.com/ikegam/surface-ultra-misc at commit
`4d00dbc292672de95de715e5e810c9860433d1a3` (2026-11-12). Ambient light
sensor (spi-hid), thermal/power daemon (`n1x-thermald`, skin temp ≤ 45 °C,
57 °C shutdown), SSAM helper modules (52 MHz UART clock + MSHW0733 clients),
power button driver, suspend hooks, USB4 dock handling, audio-jack driver,
backlight automation.

## Upstream tracking

- NVIDIA NVPCF 3.0 / carveout: https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1521
- Omarchy N1X discussion: https://github.com/omacom/omarchy/discussions/15885

## Caveats carried into the NixOS module

- Carveout ranges in `n1x_carveout_memmap.c` are hard-coded for
  `EXPOSED_DISP_FRM` = 4 GiB.
- `surface-n1x-ssam` and `n1x-surface-audio` replace in-tree drivers; their
  `n1x-dkms-guard` compares stock `srcversion` and refuses to build on a
  changed kernel (Nix: kernel-version-pinned instead).
- UCM caps RT1320 amp gain at -9 dB (no speaker protection/calibration data
  on Linux) — keep speaker volume low.
- Unplug USB4 docks before suspend (`s2idle`): `power_wrap_drv.usb4_release=0`
  is set, USB4 tunnelling handling is untested.
- Webcam needs CCU firmware extracted from Windows; camera driver otherwise
  complete for OV02C10 + IR.
