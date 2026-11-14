# surface-ultra-misc

(日本語: [README_jp.md](README_jp.md))

Small pieces for running Linux on the Microsoft Surface Laptop Ultra (NVIDIA N1X SoC, arm64).
The camera lives in its own repository, [surface-ultra-camera](https://github.com/ikegam/surface-ultra-camera).

Unofficial; not affiliated with Microsoft, NVIDIA or MediaTek. Tested on Omarchy (linux-omarchy 7.3).

## Credits

This builds on teo-casares' work bringing Omarchy up on this machine:
[the Gist](https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8) (kernel patches, DKMS modules,
services) and [omacom/omarchy discussion #15885](https://github.com/omacom/omarchy/discussions/15885).
Start there; the pieces below assume that setup.

| Directory | What | Relation to teo-casares' work |
|---|---|---|
| [`als/`](#als-ambient-light-sensor) | ambient light sensor driver | independent |
| [`thermal/`](#thermal-power-and-skin-temperature-control) | SoC power / skin temperature control, Tj safety net | independent; complements their fan daemon, and reads the SSAM temperature sensors registered by `ssam-helper` |
| [`ssam-helper/`](#ssam-helper-stock-ssam-without-patched-modules) | stock SSAM + helper modules | **their approach** (described in the discussion), implemented independently |
| [`backlight/`](#backlight-automatic-brightness) | automatic brightness | **a patch to their `n1x-edp-backlight`** (the script is not copied here) |
| [`power-button/`](#power-button) | power button driver | independent driver; the cause of the phantom "Volume Down" (floating `MSHW0040` pins) was found by them |
| [`usb4/`](#usb4-docks) | keeps the USB4 tunnel ports awake | **their approach** (described in the discussion), implemented independently |
| [`suspend/`](#suspend-sleep-and-resume) | no wakeups with the lid closed; keys dead right after resume | the lid hook is **their approach** (described in the discussion), implemented independently, with the touchpad and power button added; the NVIDIA part is independent |
| [`sapd-lps0/`](#sapd-lps0-surface-modern-standby-notifications) | sends the Surface-specific Modern Standby notifications around suspend (experimental) | independent |
| [`keyboard/`](#keyboard-caps-lock-lag) | Caps Lock lag; repeated keys through a key remapper | independent |
| [`audio-jack/`](#audio-jack-headphone-detection) | headphone jack detection | independent (upstream Realtek driver) |
| [`gpu-power/`](#gpu-power-nvidia-power-management-notes) | notes and probes on NVIDIA power management (nvidia-powerd, RATED_TDP) | independent |

## als: ambient light sensor

Exposes the ambient light sensor as the IIO device `als`:

```
$ cat /sys/bus/iio/devices/iio:device0/name
als
$ cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw    # units of 0.01 lux
36180
```

Chromaticity (x, y) is reported too. Color temperature stays 0 (the sensor hub firmware does not fill it in).

**How it works.** The sensor (ams TCS3430) sits behind a sensor hub that runs as firmware on the SoC's SCP
coprocessor. The SCP acts as an SPI slave on SPI3 and is an ACPI HID-over-SPI device: `\_SB.SENH`
(`MSFW1111`, `_CID PNP0C51`). The kernel's HID-over-SPI driver (the spi-hid series that linux-omarchy carries;
`CONFIG_SPI_HID_ACPI` is not enabled there) does not work as is, so core and ACPI glue are built out of tree
as one module, `n1x-spi-hid`, with four fixes:

1. **The reset was never sent.** `spi-hid-acpi` calls `device_reset(&adev->dev)`, but the `struct device`
   inside an `acpi_device` has no ACPI handle, so `_RST` never runs (and the error is ignored). `_RST` is now
   evaluated directly. On this machine it rings a doorbell to the sensor hub firmware.
2. **The interrupt line has no GPIO.** The `GpioInt` is pin 190, an EINT-only line: `pinctrl-mt8901` only has
   GPIOs 0-181, so the ACPI IRQ lookup fails, and `mtk-eint` would refuse `request_irq()` because it locks the
   matching GPIO. The module takes over EINT 190's flow handler and forwards it to an irq_sim interrupt
   (a reset response that arrives while the interrupt is disabled is kept by genirq and resent).
3. **A one-shot read of an input report returned the feature report.** `spi_hid_ll_raw_request()` always sends
   GET_FEATURE, so `hid-sensor-hub`'s sync read parsed settings as the illuminance. Input-report requests now
   fail, and `hid-sensor-hub` takes the next periodic report (every 750 ms).
4. **Sometimes silent after resume.** After some s2idle resumes the sensor hub sends nothing at all, not even
   the reset response, and every later report is dropped ("HID not ready"): the illuminance stays 0 and
   automatic brightness stops until the driver is rebound. If no interrupt arrives within 3 s of resume, the
   driver now resets the sensor hub again (up to 3 times) and logs `sensor hub silent after resume`.

The core exports no symbols and uses its own trace system name, so it neither replaces nor collides with the
stock `spi-hid`.

```
cd als
sudo ./install.sh     # DKMS, loaded right away and at every boot; no reboot
sudo ./uninstall.sh
```

`als/scp-peek.py` (root, read-only) prints how many reset doorbells the SCP has taken and the tail of the SCP
firmware log; useful when the device does not appear.

## thermal: power and skin temperature control

Linux does nothing here by default: none of the ACPI thermal zones has a trip point, and under a sustained CPU
load the SoC draws 64-68 W with Tj pinned at the firmware's ~98 C. On Windows the thermal policy (MPTF) keeps
the *skin* temperature (SAM sensor VTS1) at 45 C by lowering the SoC's sustained power limit: 55 W on AC,
42.5 W on battery in the default mode. This directory does the same with the knobs Linux has.

- **`n1x-thermald`** (systemd service, python3 standard library only): every 2 s it compares the averaged SoC
  power with the budget and moves every CPU's `scaling_max_freq` in 5 % steps (floor 40 %). A PI loop on the
  skin temperature (VTS1 = `surface_thermal` temp9, target 45 C; VTS5 = temp12, target 51 C) lowers the budget.
  Emergency: secondary skin >= 55.5 C or battery (RTS5 = temp5) >= 62 C pins the CPUs to their minimum,
  57 C / 64 C powers off. These are Windows' values. Without the SSAM sensors it runs on the power budget alone.
- **Tj safety net**: an extra ACPI thermal zone `\_TZ.NXTJ` (`n1x-thermal.asl`) on the SoC Tj, passive at
  100 C on all 20 CPUs, critical at 105 C. `n1x-thermal-ssdt.service` loads it through `acpi_configfs` at boot.

Two of the ACPI "thermal zones" are not temperatures: `\_TZ.PSOC` (thermal_zone2) and `\_TZ.PSYS`
(thermal_zone1) report averaged SoC and system power in mW, which is why they read "2005 C" and similar.
`n1x-thermald` uses PSOC as its power feedback.

Measured with a 19-thread load: SoC power 65 W -> 52 W, Tj 98 C -> 94 C, and back to full speed in steps once
the load stops.

```
cd thermal
sudo ./install.sh          # includes a selftest that the frequency cap really slows a CPU
./n1x-thermald --dry-run   # print decisions only, any user
cat /run/n1x-thermald/status.json
```

The fan is left to the EC (or to teo-casares' fan daemon); `n1x-thermald` does not touch it.

## ssam-helper: stock SSAM without patched modules

Patched copies of in-tree SSAM modules break on kernel updates. As teo-casares described in the discussion,
the stock modules work with two small helpers, implemented here as new modules that shadow nothing:

- `n1x_ssam_uartclk`: sets the real 52 MHz clock of the SAM UART (NVDA0240) before `surface_aggregator` opens
  it, and corrects the fractional divider that `mtk8250_set_termios()` gets wrong above 42.9 MHz (32-bit overflow).
- `n1x_ssam_clients`: a platform hub for MSHW0733 that registers battery, AC, the 11 SSAM temperature sensors
  (`surface_temp`, hwmon `surface_thermal`, tempN = SAM instance N) and fan speed (`surface_fan`).
  `profile=1` also registers the platform profile device (experimental: this EC reads back profile 0).
  It is off by default because it made no measurable difference. Sending the same requests as the stock
  `surface_platform_profile` directly (TMP cid 0x03 values 1–4, FAN cid 0x0e values 1–4), the EC accepted every
  value (status 0), but the TMP read back stayed 0. Under the same 8-thread CPU load (about 45–53 W), FAN 1, 2 and 4
  gave the same fan curve: the fan starts at about 41 °C skin and reaches about 3000 rpm at 44 °C. An effect above
  45 °C skin is not ruled out, but `thermal/` keeps the skin below that, so the fan is left to the EC.

```
cd ssam-helper
sudo ./install.sh      # replaces an installed surface-n1x-ssam/1.0 live; no reboot
sudo ./rollback.sh     # back to surface-n1x-ssam/1.0
```

## backlight: automatic brightness

`backlight/n1x-edp-backlight-auto.patch` adds automatic brightness to teo-casares' `n1x-edp-backlight` (get the
script from their Gist; the patch header has the commands). It follows Windows' lux -> nits curve for this
machine using `als`; a brightness key press is kept as an offset on top of the curve and saved across restarts;
`echo 0 > /var/lib/n1x-edp-backlight/auto` turns it off. When the level is put back at start-up or after the
panel lost it in s2idle, it fades there over about 0.3 s instead of jumping (the firmware leaves the panel at
another level, so the change was visible at every boot and resume).

## power-button

Makes the power button work. A short press sends `KEY_POWER`, which opens Omarchy's power menu.

The buttons are behind ACPI `MSHW0040` (`\_SB.MSBT`). On x86 Surfaces `soc_button_array` turns that into
gpio-keys devices, but `soc_button_array` is x86-only, so on this machine the power button has no driver. Its `_CRS`
has three GPIOs on `\_SB.GIO0`: pin 46 (power, the only one marked as a wake source) and pins 40/41. This laptop has
no volume rocker; as teo-casares found, 40/41 float and report "Volume Down" held forever. `n1x-power-button` binds
to `MSHW0040`, takes only pin 46 and leaves 40/41 alone, so `modprobe.blacklist=gpio_keys` can stay on the kernel
command line. The level at load time counts as released. A press during suspend wakes the machine but is not
reported, so the power menu does not open after resume. `install.sh` also blacklists `soc_button_array`, which
would otherwise claim `MSHW0040` on a kernel that builds it for arm64 (omacom/omarchy-pkgs#2166).

```
cd power-button
sudo ./install.sh      # DKMS, loaded at once and at every boot; no reboot
sudo ./uninstall.sh
```

Waking from suspend with the button works (tested with the lid open). If the machine sleeps with the lid closed, also
turn off the button's wakeup (`/sys/bus/platform/devices/MSHW0040:00/power/wakeup`), as for the keyboard and touchpad;
otherwise a press in a bag wakes it. The hook in `suspend/` does this.

## usb4: docks

USB4 / Thunderbolt docks need the three USB4 tunnel root ports (`10de:22cf`) kept out of runtime suspend
(teo-casares, tested with a Thunderbolt dock). `usb4/75-n1x-usb4-tunnel-pm.rules` sets `power/control=on` on them.
The other part of their setup, `power_wrap_drv.usb4_release=0`, is already the default for N1X on linux-omarchy 7.3.
They also saw suspend fail in one boot with a dock attached, so unplug the dock before suspending.

```
cd usb4
sudo ./install.sh      # applies at once; no reboot
sudo ./uninstall.sh
```

Not tested with a dock here.

## suspend: sleep and resume

**Wakeups with the lid closed.** Keys pressed in a bag wake the machine from s2idle through the I2C keyboard
(`MSHW0794`) interrupt (reported by teo-casares in the discussion, who handles it with a system-sleep hook).
`surface-ultra-lid-wakeup` is an independent implementation of the same approach. Besides the keyboard, it also turns
off wakeup for the touchpad (`MSHW0734`) and the power button (`MSHW0040`, `power-button/`), only while the lid is
closed, and turns it back on at resume. With the lid open, keys and the button still wake the machine.

**Keys dead for 10-30 s right after resume.** `nvidia-sleep.sh`, run by `nvidia-suspend.service` and
`nvidia-resume.service`, switches to VT 63 (`chvt 63`) before suspend and back after resume. Each time, Hyprland
disables and re-enables the seat and adds every input device again (`Disabling seat` / `Enabling seat` in
hyprland.log), and the lock screen gets no keys until that is done. The keyboard and I2C are fine. When the driver
runs with `NVreg_UseKernelSuspendNotifiers=1`, VRAM is saved from the kernel suspend notifiers, so the two services
are not needed. With them masked, keys work right after resume. (The lock screen's password field may still need one
click for focus; that is a separate, unsolved problem.) `NVreg_EnableS0ixPowerManagement=1` (to bring the display
back after s2idle; see teo-casares' discussion) is assumed.

```
cd suspend
sudo ./install.sh                       # hook only; applies from the next suspend
sudo ./install.sh --mask-nvidia-sleep   # also mask nvidia-suspend/resume (checks the driver settings first)
sudo ./uninstall.sh
```

## sapd-lps0: Surface Modern Standby notifications

**Experimental, under evaluation.** About 1 in 7-10 lid-close s2idle suspends never came back here: the journal ends
at `PM: suspend entry (s2idle)` and the SoC resets on its own, with no pstore record. The boot that follows then stalls
in NVIDIA GSP init (`GspStatusQueueInit ... NV_ERR_TIMEOUT`, no display). A second long press of the power button
gives a normal boot.

The firmware has two LPS0 devices (`_CID PNP0D80`) with the Microsoft Modern Standby `_DSM`
(`11e00d56-ce64-47ce-837b-1f898f9aa461`):

- `\_SB.PEPD` (`NVDA6210`): NVIDIA's platform extension. linux-omarchy's power_wrap (NVIDIA's lid-wake patch,
  NV-Kernels #656) already calls it (`LPS0 EC sleep notifications enabled` in the kernel log).
- `\_SB.SAPD` (`MSHW0299`): Surface-only. Nothing calls it on Linux. Function 7 (sleep entry) drives GPIO 136 low,
  and functions 3/4/8/9 drive it high. No other ACPI method touches that pin. On Windows it is low for the whole
  sleep; on Linux it stays high.

`n1x_sapd_lps0` binds to `MSHW0299` and sends the same sequence Windows does, in the device noirq phases: 3, 7, 5
on the way down and 6, 9, 8, 4 on the way up. Failures are logged and never block suspend. Whether this stops the
resets is not proven yet; it is being tested over a few dozen lid-close suspends. Sleep depth is unchanged (one
DRIPS per suspend).

```
cd sapd-lps0
sudo ./install.sh                                   # DKMS, loads at once, no reboot
cat /sys/bus/platform/devices/MSHW0299:00/stats     # functions=0x3f8 entries=N failures=0 enable=1
echo 0 | sudo tee /sys/module/n1x_sapd_lps0/parameters/enable   # stop sending, for an A/B test
sudo ./uninstall.sh
```

Each suspend logs `entry notifications sent (#N)` / `exit notifications sent` (module parameter `verbose`).

## keyboard: Caps Lock lag

The built-in keyboard's LED sits behind slow HID-over-I2C writes, and every write made by the `kbd-capslock` LED
trigger to follow the key state delays Caps Lock itself. `73-surface-capslock-led.rules` sets the trigger of the
built-in keyboard's Caps Lock LED to `none`. The LED no longer lights, but the lag is gone.

```
cd keyboard
sudo ./install.sh      # applies at once; no reboot
sudo ./uninstall.sh
```

**Repeated keys through a key remapper.** On this keyboard a key release sometimes arrives very late (hundreds of
ms), only about 15 ms before the next key press (cause under investigation; the handling of GPIO interrupt EINT 139 is
suspected). A raw capture of the keyboard had no press shorter than 20 ms, but keyd's virtual keyboard showed several
3-17 ms presses, which looked like repeated keys. Do remaps such as Caps→Ctrl with Hyprland (`kb_options =
ctrl:nocaps`, key bindings) instead of keyd.

## audio-jack: headphone detection

With the rt721-sdca driver in linux-omarchy 7.3, plugging headphones into the 3.5 mm jack is not detected: the
`Headphone Jack` control stays off and PipeWire keeps playing through the speakers. On insertion the RT721 never
raises its jack-detection interrupt (SDCA interrupt 0); only Function_Status (interrupt 3) arrives. Removal is
detected. The rt721-sdca driver from Linux v7.4-rc1 fixes this; it includes Realtek's rework of the jack-detection
setup (`e2eb4873b901` "Adjust blindwrite flow to fix type detection issue") and related changes. This directory
builds that driver unchanged for 7.3 kernels (DKMS `BUILD_EXCLUSIVE_KERNEL` is `^7\.3\.`; 7.4 has it in tree).

```
cd audio-jack
sudo ./install.sh      # DKMS, then rebuilds the sound card at once; no reboot
sudo ./uninstall.sh    # back to the kernel's module
```

`install.sh` stops PipeWire for a few seconds while the card is rebuilt.

## gpu-power: NVIDIA power management notes

Notes from looking into why some N1X laptops hold the GPU at ~750 MHz on AC while this one does not. Driver
620.70.06 (open kernel modules), linux-omarchy 7.3. Nothing here is needed to run the machine.

- **The firmware already caps the SoC.** With the CPU and GPU both under full load, the averaged SoC power (ACPI
  `\_TZ.PSOC`) settles at 80.0 W and the GPU lowers its own clock (2132 → 1976 MHz). What the OS still has to do
  is keep the skin temperature down, which `thermal/` does.
- **nvidia-powerd (Dynamic Boost) does not help here.** The firmware answers the NVPCF `_DSM` only at revision
  0x300. The 620 daemon reads the 3.x config but creates no worker ("No Worker Running!"); its worker factory
  creates workers only on the 1.x/2.x path. Made to see 2.x data (`nvpcf-shim/`), QBoost runs, but it reacts only
  to NVPCF events from the platform firmware, its GPU limit write (private control `0x2080e634`) is answered
  `NOT_SUPPORTED`, and its CPU limit goes to an SBIOS `_DSM`.
- **RATED_TDP is what sets the ~750 MHz floor, as far as I can tell.** Setting `RATED_TDP` client GLOBAL to
  FORCE_LIMIT drops the GPU under load from 2379 MHz / 49.6 W to 741 MHz / 12.5 W, and DEFAULT restores it.
  `ctrl2080perf.h` says the RM client, which has the highest priority, asks for FORCE_LIMIT "when no power
  controllers are active". On this machine every client, the RM client included, reads DEFAULT.
- The NVPCF 3.0 init table (subfunction 1) is AES-encrypted. The key ships inside the driver's user-space
  daemon, so the table can be read; neither the key nor a decryptor is published here.

### ratedtdp-probe

Read-only. Prints the RATED_TDP request of each arbitration client, using the RM handles of the program it is
preloaded into. No root needed.

```
cd gpu-power/ratedtdp-probe && make
LD_PRELOAD=$PWD/ratedtdp-probe.so nvidia-smi -L
```

```
RATED_TDP RM      rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP WAR     rc=0 status=0 action=0 DEFAULT vpstate=0
RATED_TDP GLOBAL  rc=0 status=0 action=0 DEFAULT vpstate=0
...
```

### nvpcf-shim (experiment)

An `LD_PRELOAD` shim that lets nvidia-powerd 620 start its QBoost worker on N1X: it hides NVPCF 3.x, answers the
2.x queries, names a TGP power policy, emulates the x86 RAPL MSRs the daemon reads, reports the AC state from
`ADP1`, and logs every RM control so the daemon's control targets can be seen. It is for study, not for daily use.
Build with `make` (it needs the SDK headers of the matching open-gpu-kernel-modules), then run the daemon with
`LD_PRELOAD` and the `SHIM_*` variables described at the top of the file.

## License

GPL-2.0 (see LICENSE). The spi-hid sources in `als/` come from the spi-hid series carried by linux-omarchy
(Microsoft, Google, Semihalf and others); each modified file says what was changed.
The rt721-sdca sources in `audio-jack/` are Realtek's (GPL-2.0-only), copied unmodified from Linux v7.4-rc1.
