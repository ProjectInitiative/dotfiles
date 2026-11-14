# surface-ultra-tools — userspace services & scripts for the Surface Laptop Ultra
#
# Userspace pieces from the teo-casares gist (vendored under
# vendor/surface-ultra/gist-teo-casares/), packaged without modification:
#
#   n1x-touchpad-ptp         rebinds the ELAN 04F3:3358 touchpad as
#                            MT_CLS_WIN_8 via a dynamic hid-multitouch id —
#                            the runtime fallback when kernel patch 0004
#                            is not in the kernel
#   kbd-repeat-delay         sets the kernel soft-autorepeat delay on an
#                            evdev node (used by the console udev rule; the
#                            keyboard's key-release reports arrive 20-145 ms
#                            late, so the 250 ms default self-repeats)
#   n1x-edp-backlight        creates /sys/class/leds/nvidia_0::lcd_backlight
#                            (0-100 -> 3-1000 nits over eDP DPCD) through
#                            the NVIDIA RM ioctl interface, persists level
#   surface-kbd-backlight    creates /sys/class/leds/surface::kbd_backlight
#                            (levels 0/3/6/12) over the keyboard's HID
#                            backlight control
#   n1x-sdw-settle           one soft SoundWire link reset after the card
#                            appears (safety net for a half-initialised
#                            jack codec)
#
# These scripts hardcode /usr/local/bin paths in their shebang-adjacent
# comments only; the NixOS module installs them into the systemd PATH via
# the packaged unit files.
{
  lib,
  stdenvNoCC,
  bash,
  python3,
  makeWrapper,
  gawk,
  gnugrep,
  coreutils,
  kmod,
}:

stdenvNoCC.mkDerivation {
  pname = "surface-ultra-tools";
  version = "unstable-2026-11-13";

  src = ../../../vendor/surface-ultra/gist-teo-casares;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/systemd/system

    install -Dm755 n1x-touchpad-ptp $out/bin/n1x-touchpad-ptp
    install -Dm755 kbd-repeat-delay $out/bin/kbd-repeat-delay
    install -Dm755 n1x-edp-backlight $out/bin/n1x-edp-backlight
    install -Dm755 surface-kbd-backlight $out/bin/surface-kbd-backlight
    install -Dm755 n1x-sdw-settle $out/bin/n1x-sdw-settle

    for svc in n1x-edp-backlight n1x-sdw-settle n1x-touchpad-ptp surface-kbd-backlight; do
      install -Dm644 $svc.service $out/lib/systemd/system/$svc.service
      substituteInPlace $out/lib/systemd/system/$svc.service \
        --replace-fail "/usr/local/sbin/$svc" "$out/bin/$svc" \
        --replace-fail "/usr/local/bin/$svc" "$out/bin/$svc"
    done

    # python3 shebang script (uses only the stdlib)
    wrapProgram $out/bin/kbd-repeat-delay \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          coreutils
        ]
      }
    # bash scripts need standard tools
    for s in n1x-touchpad-ptp n1x-edp-backlight surface-kbd-backlight n1x-sdw-settle; do
      wrapProgram $out/bin/$s \
        --prefix PATH : ${
          lib.makeBinPath [
            bash
            gawk
            gnugrep
            coreutils
            kmod
          ]
        }
    done
    runHook postInstall
  '';

  meta = with lib; {
    description = "Userspace services and scripts for the Surface Laptop Ultra (touchpad PTP rebind, eDP/keyboard backlights, SoundWire settle, key repeat)";
    platforms = [ "aarch64-linux" ];
  };
}
