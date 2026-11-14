# Omarchy on the Microsoft Surface Laptop Ultra (NVIDIA N1X): the whole journey

Written 2026-10-18. This document collects everything it took to go from "the Omarchy aarch64 ISO boots to a
dead machine" to a daily-driver laptop: what broke, how each cause was found, what fixed it, where the fix
lives, and what should go upstream so the next person doesn't have to repeat any of it.

The detailed working notes this is distilled from:
- `~/omarchy-n1x-issues.md`: boot, Limine/GRUB, NVIDIA carveout investigation (test-by-test)
- `~/SURFACE-OMARCHY-ISSUES.md`: overall status, disk layout, ACPI findings, webcam
- `~/surface-laptop-ultra-issues.md`: touchpad investigation
- `~/omarchy-n1x/driver-fixes/README.md`: battery, audio, mic, keyboard, brightness, kernel-update procedure
- `~/omarchy-n1x/driver-fixes/CHANGELOG*.md`: raw timestamped change log with per-change revert steps

---

## The machine

| | |
|---|---|
| Model | Microsoft Surface Laptop Ultra, SKU `Surface_Laptop_Ultra_2115`, UEFI 7.1.0 (Microsoft Project Mu) |
| SoC | NVIDIA N1X ("RTX Spark", GB10 family, aarch64), MediaTek-derived platform blocks |
| GPU | `10de:2e03`, "NVIDIA RTX Spark N1X (6144-core Blackwell RTX GPU)", unified memory |
| RAM / disk | 64 GB / Micron 4600 NVMe |
| Wi-Fi / BT | MediaTek MT7925 |
| Input | Keyboard `MSHW0794`, touchpad ELAN `MSHW0734` `04F3:3358`, touchscreen/pen `MSHW0735` `1FD2:4003` (all I2C HID) |
| Embedded controller | Surface SAM `MSHW0084` over UART `NVDA0240` (`8250_mtk`), platform ID `MSHW0733` |
| Audio | MT8901 AFE + SoundWire link 0 (`NVDA9100`): 2x Realtek RT1320 amps (speakers + mic array), RT721 (jack) |
| Camera | OmniVision OV02C10 (RGB) + SMO55F1 (IR) behind an "mt8991" seninf/camsys/CCU block |
| OS | Omarchy 4 "Quattro" aarch64, `linux-omarchy` 7.2.8 (started on -11, now -13), Hyprland (Lua config) |
| Secure Boot | Off |

Disk: p1-p4 are Windows (ESP, MSR, C:, WinRE) and were never touched; p5 is the Omarchy ESP (`/boot`, 2 GB FAT);
p6 is LUKS with btrfs root. Dual boot with Windows keeps working.

## Final scorecard

| Area | Before | After | How |
|---|---|---|---|
| USB, I2C, SPI (so: keyboard, touchpad, USB) | dead | **works** | kernel arg `acpi_osi=!` |
| Phantom Volume Down key spam | console flooded | **gone** | `modprobe.blacklist=gpio_keys` (side buttons lost) |
| Booting from internal disk | Limine reset loop | **works** | GRUB on the ESP instead of Limine |
| Wi-Fi | NetworkManager masked | **works** | unmasked NM |
| Touchpad pointer | never moved | **works** | libinput quirk |
| Touchpad palm rejection | none | **works** (needs a reboot test) | rebind as `MT_CLS_WIN_8` |
| NVIDIA GPU | hard reset on load | **works**: Hyprland, OpenGL 4.6, Vulkan 1.4 | carveout memmap module + patched driver (DKMS) |
| Battery / AC | no `/sys/class/power_supply` | **works** | DKMS `surface-n1x-ssam` |
| Screen brightness + keys | no backlight device | **works** | `n1x-edp-backlight` service (eDP DPCD nits) |
| Keyboard backlight | none | **works** | `surface-kbd-backlight` service |
| Key repeat ("microoooophone") | doubled letters | **worked around** | 500 ms repeat delay |
| Speakers, headphone jack | Dummy Output | **works** | DKMS `n1x-surface-audio` + UCM + settle service |
| Internal mic array | none | **works** | same as speakers |
| Webcam | none | **blocked** | no Linux driver for the camera block |
| Volume / power side buttons | stuck | disabled | needs a `soc_button_array` quirk |
| USB4 power (`usb4_release=0`) | - | disabled, untested | risky: can reset the SoC |
| Suspend/resume, external displays, CUDA | - | untested | |

Benchmarks once the GPU worked: glmark2-wayland 5119, vkmark 2560x1600 4282 (61% GPU, 2535 MHz, 36.6 W); 24 GiB of
GPU buffers resident at once with exact read-back; ~230 GB/s memory traffic.

---

## Chapter 1: Getting it to boot at all

### 1.1 The machine boots, but nothing works (`acpi_osi=!`)
**Symptom:** no USB, no internal keyboard or touchpad, no I2C or SPI.

**Cause:** the Surface DSDT (DSDT:15614/15738/15787, SSDT3:2542/2559) returns `_STA=0` for five devices when
`_OSI("Windows 2022")` is true, and Linux answers yes to Windows `_OSI` strings:
SVP0 (`NVDA3000`), SSPM (`NVDA8400`), HFRP (`MTK00055`), NH1X (`NVDA300A`), NMAP (`NVDA300B`).
SSPM never binds, `mtk_pwrap` fails (`scmi ret = -19`), and xHCI/I2C/SPI probes fail with -22.

**Fix:** kernel argument `acpi_osi=!`. Those five are the only `_OSI` uses in all the tables, so it's a narrow
change. All five now report `sta=15`.

### 1.2 Phantom key spam (`^[[26~` on the console)
**Cause:** the Volume Down side button (`MSHW0040` → `soc_button_array` → `gpio-keys`) reports itself held forever
(236 repeats in 8 s, untouched).

**Workaround:** `modprobe.blacklist=gpio_keys`. Cost: the hardware volume and power side buttons don't work.
A real fix needs a `soc_button_array` quirk for `MSHW0040` or a GPIO polarity fix.

### 1.3 Limine resets the machine before drawing anything
**Symptom:** the firmware entry for Limine loops on the Surface logo. No menu even with `quiet: no`, `timeout: 5`,
`graphics: no`, `verbose: yes`. Every working boot came through the USB stick's GRUB.

**Ruled out:** a corrupt binary (byte-identical to the package), a stale config overriding `/boot/limine.conf`
(omarchy #3335), a wrong firmware device path, Secure Boot, the UEFI watchdog (Limine 12.9.3 disables it).
Limine itself is fine in QEMU/edk2 with a copy of the ESP: it shows the menu and boots the UKI. The failure is
specific to this Project Mu firmware.

**Most likely causes** (from Limine 12.9.3 source; both happen before anything is drawn, neither is confirmed):
1. `init_memmap()` claims nearly all RAM and leaves the firmware only 64 MiB below 4 GiB; this machine has only
   ~1.8 GiB of fragmented RAM below 4 GiB. ARM firmware is known to be sensitive to this (limine #521).
2. `disk_create_index()` runs `ConnectController(recursive)` on every storage handle and reads every disk. Limine's
   own comment says this makes "some buggy firmware misbehave, up to spontaneous resets".

Confirming which one needs an instrumented Limine build and reboots on the hardware, so we went around it.

**Fix: boot through GRUB from the Omarchy ESP.**
- `/boot/EFI/omarchy-n1x/grubaa64.efi`: the USB stick's GRUB (already proven on this firmware), with only its
  embedded config changed to load `/EFI/omarchy-n1x/grub.cfg` from p5.
- `/boot/EFI/omarchy-n1x/grub.cfg` (hand-written): Omarchy (NVIDIA) default, Omarchy without NVIDIA, text console,
  fallback image, Windows, Limine (testing only), UEFI Firmware Settings. GRUB chainloads the same UKIs in
  `/EFI/Linux/` that `limine-update`/mkinitcpio rebuild, so kernel updates keep working.
- Tested first in QEMU/KVM against the real NVMe (read-only through a qcow2 overlay): both entries reached the real
  LUKS prompt.
- `~/omarchy-n1x/switch-to-grub.sh` registered `Boot0006 "Omarchy (GRUB)"` safely: it saved the old BootOrder, put
  Windows first and used BootNext for a one-time GRUB boot, so a failure would land in Windows instead of looping.
  After one good boot, `omarchy-n1x-grub-promote.service` moved GRUB to the front. Limine is kept, last in the order.

**Downsides:** kernel arguments live in `grub.cfg` (they override the UKI's built-in cmdline), so edits under
`/etc/limine-entry-tool.d` must be mirrored by hand; snapshot boot entries from limine-snapper-sync don't appear.

### 1.4 Other boot settings that matter
- Already from Omarchy's N1X support: `console=tty0 acpi=nospcr`, `mem_sleep_default=s2idle`, `pci=hpbussize=0x20`.
- `initramfs_async=0`, `plymouth.enable=0`, `zswap.enabled=0`.
- `power_wrap_drv.usb4_release=0` (Omarchy's USB4 setting, validated only on the ASUS ProArt P14 and Dell XPS 16)
  is **disabled** here: the kernel README warns a bad SSPM USB4 power request resets the SoC, and it was never needed.
- `initcall_blacklist=simpledrm_platform_driver_init` was disabled while NVIDIA was blocked (it would leave no
  display at all); with NVIDIA working, the default entry doesn't need it either.

### 1.5 Small things
- NetworkManager had been masked; unmasked and enabled (`NetworkManager-wait-online` stays masked).

---

## Chapter 2: The touchpad

### 2.1 The pointer never moves
Touches were detected (MT slots, tracking IDs, IRQs firing, continuous contacts in raw HID), but the cursor never
moved. The Confidence-bit theory was wrong (Confidence = 1 in 1,602 of 1,733 reports).

**Cause (confirmed by A/B replay through a fresh libinput):** the pad advertises pressure 0-2048 but real fingers
report ~1-40, so libinput's pressure threshold (204:245) rejected every touch.

**Fix:** `/etc/libinput/local-overrides.quirks`:
```
[Surface Laptop Ultra Touchpad]
MatchUdevType=touchpad
MatchBus=i2c
MatchVendor=0x04F3
MatchProduct=0x3358
AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
```
`AttrInputProp=+INPUT_PROP_PRESSUREPAD` (the style libinput upstream uses for Elan 04F3:3355) behaves identically
in replay and is the better upstream candidate.

### 2.2 No palm rejection
**Cause:** the pad is a Windows Precision Touchpad with a per-contact Confidence bit, but its PTPHQA blob
(usage `0xff0000c5`) is 4 bytes instead of 256, so hid-core groups it as generic multitouch and hid-multitouch never
maps Confidence → `MT_TOOL_PALM`.

**Fix:** `n1x-touchpad-ptp.service` → `/usr/local/sbin/n1x-touchpad-ptp` adds a hid-multitouch dynamic id
(`18 04f3 3358 12`, i.e. `MT_CLS_WIN_8`) and rebinds. **Upstream fix:** a `hid-multitouch` device-table entry for
`04F3:3358` with `MT_CLS_WIN_8`.

---

## Chapter 3: The NVIDIA GPU

This was the hardest part and the most interesting finding.

### 3.1 Loading the driver hard-resets the machine
GSP firmware boots fine, but when nvidia-drm (modeset=1) creates its device:
```
WARNING: mm/vmalloc.c:576 vmap_small_pages_range_noflush
  nv_vm_map_pages ← nv_alloc_kernel_mapping ← osMapSystemMemory ← … ← nvkms AllocateDevice
NVRM: failed to map pages!
nvidia-modeset: Unable to allocate LUT memory from sysmem
```
then an oops in `nvSetupOutputLUT5` and a hard reset.

### 3.2 Root cause: the GPU carveout has no `struct page`
- Omarchy already sets `EXPOSED_DISP_FRM` to 4 GiB (migration `omarchy-apply-n1x-gpu-memory`).
- On the Dell/ASUS N1X machines that region shows in `/proc/iomem` as `reserved`, i.e. it is in memblock and has
  `struct page`s. On the Surface it is **absent from the EFI memory map altogether** (confirmed with `efi=debug`:
  the map jumps from `0x1fcffffff` to `0x300000000`), so Linux never creates a memmap for it.
- The IORT has an RMR node giving exactly those ranges (`0x200000000+4G`, `0xa1600000+386M`, plus the boot
  framebuffer) to the GPU's stream IDs. The firmware deliberately hides the carveout from the OS.
- The driver hands out carveout pages and maps them with `vmap()`, which needs a valid `struct page`. The failing
  page (`0x27fffb000`) decodes from the WARN registers to inside the hole; a throwaway `pfn_valid` probe module
  confirmed the whole `0x200000000-0x2ffffffff` block has no memmap.

### 3.3 First attempt: map carveout pages with `vmap_pfn()` (failed)
The patch picked the new path by checking only the allocation's first page. Allocations turned out to be
**scattered, mixing RAM pages with carveout pages**, and no exported kernel primitive maps such a mixed list.

### 3.4 Fix: give the carveout a memmap
- New module `n1x_carveout_memmap` (DKMS `n1x-carveout-memmap/1.0`): `memremap_pages(MEMORY_DEVICE_PRIVATE)` over
  `0x200000000-0x2ffffffff` and `0xa1600000-0xb7ffffff`. This creates `struct page`s with **no linear mapping**,
  the same state the Dell/ASUS firmware gives the carveout. ~10 ms per range, ~70 MiB of memmap.
- With it loaded, the **stock** `vmap()` path handles every mapping. The driver patch
  (`nvidia-615.78.08-n1x-carveout.patch`, via `/etc/dkms/nvidia/patches/` + `/etc/dkms/nvidia-615.78.08.conf`) adds
  fallbacks for pages without a struct page; in practice the fallback never ran.
- Load order: `/etc/mkinitcpio.conf.d/nvidia.conf` → `MODULES+=(n1x_carveout_memmap nvidia nvidia_modeset
  nvidia_uvm nvidia_drm)`; `/etc/modprobe.d/n1x-carveout-memmap.conf` → `softdep nvidia pre: n1x_carveout_memmap`.
- Result: 0 WARNINGs, `card1-eDP-1: connected`, Hyprland on NVIDIA, OpenGL 4.6, Vulkan 1.4.
- Caveat: ranges are hard-coded for `EXPOSED_DISP_FRM` = 4 GiB.

**Upstream:** this is a firmware/driver mismatch, not a Surface hack. The clean fix is either the Surface firmware
listing the carveout as reserved in the EFI memory map, or the NVIDIA driver (or kernel platform code) creating a
`ZONE_DEVICE` memmap for IORT RMR ranges that are missing from it. Worth reporting to NVIDIA
(open-gpu-kernel-modules) and Omarchy's N1X kernel.

---

## Chapter 4: Battery and the Surface embedded controller

**Symptom:** `/sys/class/power_supply/` empty.

**Cause:** battery data comes only from the Surface SAM EC, over UART `NVDA0240` (`8250_mtk`) at 4 Mbaud. The ACPI
path of `8250_mtk` hardcodes a 26 MHz UART clock but the real clock is ~52 MHz, so the link ran at ~8 Mbaud and the
EC ignored it (`surface_serial_hub: failed to get firmware version`). Also, `surface_aggregator_registry` has no
entry for platform `MSHW0733`.

**Fix:** DKMS `surface-n1x-ssam/1.0`:
- patched `surface_aggregator` requests half the baud on `NVDA0240` (a true 4 Mbaud). The EC reports firmware 6.68.102.
- patched `surface_aggregator_registry` adds `MSHW0733` with **battery and AC only** (the EC's HID devices are left
  out so they can't fight the I2C keyboard/touchpad).
- stock `surface_battery`/`surface_charger` then create `BAT1`/`ADP1`.

**Proper upstream fix:** `8250_mtk` using 52 MHz for `NVDA0240` (patch staged at
`driver-fixes/scratch-archive/driver-work/battery/STAGED-8250_mtk-nvda0240-52mhz.patch`) plus the `MSHW0733`
registry entry in linux-surface / platform-drivers-x86.

---

## Chapter 5: Keyboard

### 5.1 Doubled letters ("microoooophone")
**Cause (measured):** the keyboard sometimes delivers its "all keys released" report 20-145 ms late, in bursts, so
with a 250 ms repeat delay ordinary keystrokes auto-repeated. The I2C bus (i2c-3, shared with the touchpad) stalls;
why is unproven (clock stretching, or ~100 kHz vs ACPI's 400 kHz).

**Workaround:** repeat delay 500 ms / rate 40: `repeat_delay = 500` in `~/.config/hypr/input.lua`, and for the
console `/etc/udev/rules.d/71-key-repeat-surface-kbd.rules` → `/usr/local/bin/kbd-repeat-delay`.

### 5.2 Keyboard backlight
**Cause:** the keyboard exposes a HID backlight control (levels 0/3/6/12) but no kernel driver turns it into an LED.

**Fix:** `surface-kbd-backlight.service` creates `/sys/class/leds/surface::kbd_backlight` (0-3) and forwards
changes. Upstream candidate: a small HID driver.

---

## Chapter 6: Screen brightness

**Cause:** no `/sys/class/backlight`. NVIDIA registers one only when a firmware brightness query succeeds, and it
fails here; the ACPI fallback has levels but no set method. The panel takes a target luminance in nits over eDP DPCD.

**Fix:** `n1x-edp-backlight.service` creates `/sys/class/leds/nvidia_0::lcd_backlight` (0-100 → 3-1000 nits) through
the NVIDIA RM ioctl interface, and persists the level. Brightness keys are rebound in `~/.config/hypr/bindings.lua` to
`~/.local/bin/n1x-brightness-display`, which hands back to `omarchy-brightness-display` if a real backlight appears.

**Upstream:** NVIDIA driver backlight registration fallback for eDP panels that take luminance in nits.

---

## Chapter 7: Speakers, headphone jack and microphone

**Symptom:** only HDMI audio and "Dummy Output". SoundWire logged bus clash / parity storms on link 0, then
`no card from this controller`.

**Causes:**
1. SoundWire link-0 pads (GPIO66/67) were at 2 mA drive strength. ACPI asks for 8 mA but the driver ignores it, so
   the bus never synced cleanly and no codec attached reliably.
2. `soundwire-mtk`'s machine table had no entry for this codec layout (2x RT1320 + RT721; the mic array is wired to
   the first amp's mic function), so no sound card was created.

**Fix:** DKMS `n1x-surface-audio/1.0`:
- `soundwire-mtk` = Omarchy's in-tree driver + `surface-ultra-mach.patch` (verified byte-for-byte against stock with
  the patch reverted).
- `sdw_pad_drive` sets GPIO66/67 to 8 mA, loaded before `soundwire_mtk` via `/etc/modprobe.d/n1x-audio-sdw-pads.conf`.
- UCM: `/usr/share/alsa/ucm2/conf.d/mt8901-soundwir/MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf`
  + `HiFi-surface-laptop-ultra.conf`. **RT1320 gain capped at -9 dB**: Linux has no Realtek speaker protection /
  calibration data for these amps, so avoid very loud playback.
- `n1x-sdw-settle.service`: one soft link reset after the card appears (safety net for a half-initialised jack codec).

**Upstream:** pad drive strength from the ACPI PinFunction data and the machine-table entry (Omarchy kernel /
NVIDIA's MT8901 series); the UCM profile (alsa-ucm-conf).

---

## Chapter 8: Webcam (blocked)

- Front camera OmniVision OV02C10 (`OVTI02C1`, i2c-0 0x36), IR camera `SMO55F1`. Both described in SSDT6 without
  `_DSD`/graph/clock; GPIOs are only named through a Windows `_DSM`.
- The sensor is alive: powered by hand via GPIOs (avdd 103, campower 39, mclk-gate 76, reset 81, privacy LED 43), it
  returned chip ID `0x560243`.
- **Blocker:** no Linux driver for the MediaTek-derived camera block (seninf `NVDA2820`, camsys/ISP `NVDA2801-2803`,
  CCU + firmware); Windows calls it "mt8991". NVIDIA's own N1X Ubuntu kernel doesn't have one either.
- **Use instead:** any USB UVC webcam.

---

## Chapter 9: Keeping it working across updates

- Every kernel-side fix is DKMS, so pacman's DKMS hook rebuilds them for each new kernel, before the UKI is rebuilt
  (hook 70 before 90), which matters because the initramfs includes `nvidia` and `n1x_carveout_memmap`.
- The two packages that carry patched copies of in-tree drivers (`n1x-surface-audio`, `surface-n1x-ssam`) have a
  `PRE_BUILD` guard, `n1x-dkms-guard`: it compares the new kernel's stock module `srcversion` with the one the patch
  was made against, and refuses to build (leaving `/var/lib/n1x-dkms-guard/*.NEEDS-REBASE`) if the driver changed.
  The system then falls back to the stock driver instead of loading a stale copy. Rebase steps are in
  `driver-fixes/README.md`.
- The NVIDIA patch is pinned to 615.78.08; a new driver version builds stock (the memmap module is what really fixes
  it). After an NVIDIA update, re-check brightness (it uses the RM ioctl interface).
- Verified: the 7.2.8-11 → 7.2.8-13 update rebuilt everything, and the first reboot on the default GRUB entry passed
  the checklist (battery, charger, all four audio endpoints, both backlights, key repeat).
- Take a snapper snapshot before updates: `sudo snapper -c root create -d "before update"`.

## After a kernel update or reboot, check

```
dkms status
ls /var/lib/n1x-dkms-guard/        # any *.NEEDS-REBASE = a fix was skipped for that kernel
upower -d                          # BAT1 + ADP1
wpctl status                       # speakers, headphone jack, mic
brightnessctl -l                   # nvidia_0::lcd_backlight, surface::kbd_backlight
```

---

## Complete inventory of changes on this machine

### Kernel command line (in `/boot/EFI/omarchy-n1x/grub.cfg`, mirrored in `/etc/limine-entry-tool.d/90-surface.conf`)
`acpi_osi=! modprobe.blacklist=gpio_keys module_blacklist=nouveau pci=hpbussize=0x20 mem_sleep_default=s2idle
console=tty0 acpi=nospcr zswap.enabled=0 initramfs_async=0 plymouth.enable=0 loglevel=4`

### Boot
- `/boot/EFI/omarchy-n1x/grubaa64.efi`, `/boot/EFI/omarchy-n1x/grub.cfg`, firmware entry `Boot0006 "Omarchy (GRUB)"`
- `omarchy-n1x-grub-promote.service` (+ `~/omarchy-n1x/omarchy-n1x-grub-promote`, `switch-to-grub.sh`)
- Limine left installed, last in BootOrder; `/etc/limine-entry-tool.d/00-omarchy-n1x-{gpu,usb4}.conf.disabled`

### DKMS packages (`/usr/src/…`)
- `n1x-carveout-memmap/1.0`: GPU carveout memmap
- `nvidia/615.78.08` + `/etc/dkms/nvidia/patches/n1x-carveout.patch` + `/etc/dkms/nvidia-615.78.08.conf`
- `surface-n1x-ssam/1.0`: battery/AC (with `n1x-dkms-guard`)
- `n1x-surface-audio/1.0`: speakers/jack/mic (with `n1x-dkms-guard`)

### Module config
- `/etc/mkinitcpio.conf.d/nvidia.conf` (memmap module first)
- `/etc/modprobe.d/n1x-carveout-memmap.conf`, `/etc/modprobe.d/n1x-audio-sdw-pads.conf`

### Services and scripts
- `n1x-edp-backlight.service` → `/usr/local/sbin/n1x-edp-backlight`
- `surface-kbd-backlight.service` → `/usr/local/sbin/surface-kbd-backlight`
- `n1x-sdw-settle.service` → `/usr/local/sbin/n1x-sdw-settle`
- `n1x-touchpad-ptp.service` → `/usr/local/sbin/n1x-touchpad-ptp`
- `/etc/udev/rules.d/71-key-repeat-surface-kbd.rules` → `/usr/local/bin/kbd-repeat-delay`

### Userspace config
- `/etc/libinput/local-overrides.quirks` (touchpad pressure)
- UCM profile under `/usr/share/alsa/ucm2/conf.d/mt8901-soundwir/`
- `~/.config/hypr/input.lua` (`repeat_delay = 500`), `~/.config/hypr/bindings.lua` (brightness keys),
  `~/.local/bin/n1x-brightness-display`

Copies of every installed file are in `~/omarchy-n1x/driver-fixes/installed-files/`, the replaced originals in
`driver-fixes/backups/`, and revert steps for each change in `driver-fixes/README.md`.

---

## What should go upstream, and where

| Fix | Belongs in | Form |
|---|---|---|
| `acpi_osi=! modprobe.blacklist=gpio_keys` on this DMI | Omarchy N1X hardware setup | DMI-matched kernel args |
| GRUB instead of Limine on this firmware | Omarchy installer / ISO | per-device bootloader choice, or a Limine fix |
| GPU carveout memmap | NVIDIA open-gpu-kernel-modules, Omarchy N1X kernel | driver/kernel handling of RMR ranges missing from the EFI map |
| `8250_mtk` 52 MHz for `NVDA0240` | Omarchy kernel (`omarchy-pkgs`), upstream serial | kernel patch |
| `MSHW0733` in `surface_aggregator_registry` | linux-surface / platform-drivers-x86 | kernel patch |
| SoundWire pad drive + machine-table entry | Omarchy kernel (`1030-n1x-audio.patch`), NVIDIA MT8901 series | kernel patch |
| UCM profile | alsa-ucm-conf (or Omarchy defaults) | config files |
| Touchpad pressure quirk | libinput | `50-system-*.quirks` entry |
| Touchpad `MT_CLS_WIN_8` | hid-multitouch | device-table entry |
| Keyboard backlight | Omarchy (service) or a HID driver | |
| eDP nits backlight | NVIDIA driver | registration fallback |
| Volume Down stuck | `soc_button_array` | quirk for `MSHW0040` |
