# Surface Laptop Ultra (N1X) — pinned upstream sources
#
# Single place for every external source the SLU packages/modules build
# from. Update a pin here; every consumer follows.
#
# Sources:
#   - teo-casares gist (kernel patches, DKMS modules, services, configs):
#       https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8
#     Gists have no commit pinning, so we pin the raw per-file URLs the gist
#     API reports (revision 219814edf... recorded 2026-11-13). Upstreaming
#     any file changes its raw_url, so a drift fails the hash — deliberate:
#     SLU patches are kernel-version-sensitive and must not float silently.
#   - ikegam/surface-ultra-camera @ e95a232 (2026-11-10): MT8991 camera ISP
#   - ikegam/surface-ultra-misc   @ 4d00dbc (2026-11-12): thermald, ssam-helper,
#     power button, suspend hooks, USB4 rules
#
# To update: bump rev/url, then `nix build` and copy the "got: sha256-…"
# from the hash mismatch into `hash` (or `nix store prefetch-file --unpack
# <url> --json` to pre-compute).
{
  lib,
  fetchurl,
  fetchFromGitHub,
}:

let
  gistBase = "https://gist.githubusercontent.com/teo-casares/8b64949638e1952602a7f435bb34d5b8/raw";

  # Per-file pinned fetch of the gist artifacts (raw_url pins from the gist
  # API at fetch time 2026-11-13).
  gistFile = name: hash:
    fetchurl {
      url = gistBase + "/${name}";
      inherit hash;
    };
in
{
  # --- gist artifacts -----------------------------------------------------
  gist = {
    inherit gistFile;

    n1xCarveoutMemmapC = gistFile "n1x_carveout_memmap.c" "sha256-1JDTx+5KlpPTJTDWQwI9v99N5DHpTqon+m/IShVzYt0=";
    n1xCarveoutMemmapMakefile = gistFile "n1x_carveout_memmap.Makefile" "sha256-uWinl+Q8kvzJZzKbBy1FUVzhvGJy3W8kZtDXcaZ/mBY=";
    n1xCarveoutMemmapModprobe = gistFile "n1x-carveout-memmap.modprobe.conf" "sha256-8qU4DRZqvJr4g2UTyX0hQ0/kRWq0Qfxu2cCVfINdyzk=";
    n1xCarveoutPatch = gistFile "nvidia-615.78.08-n1x-carveout.patch" "sha256-+AJqGsTzXbGii1eHREZ8Z1sB6Q/33TZK5PHK0zFd/Bo=";

    sdwPadDriveC = gistFile "sdw_pad_drive.c" "sha256-xzRBlVpK/mC52SmFkjodB4j9vY/L0prR8lPZ7LcvXno=";
    n1xAudioSdwPadsConf = gistFile "n1x-audio-sdw-pads.conf" "sha256-GdwbLY3PXPZIdp7PRU6bzGkLiQC9zEKeRMSyOSNPZ1w=";
    surfaceUltraMachPatch = gistFile "surface-ultra-mach.patch" "sha256-YIPjzMSLrYbVLW0Ue8x7C0GGEX0IzGYy2sT9jAQbITw=";

    surfaceN1xSsamPatch = gistFile "surface-n1x-ssam.patch" "sha256-4fekJVYIcsyOmhdceVEhzXnRqQzMJEVmWP9n8/xdyZs=";
    staged8250MtkPatch = gistFile "STAGED-8250_mtk-nvda0240-52mhz.patch" "sha256-QxG0XHcmePFO3/0CJ4U6cGaL/EM1Ugqx1Ii2um9NkIo=";

    ucmCardConf = gistFile "MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf" "sha256-pumgvHAr8IvBjo6Y5+4O2bavOscSlnjEO749tWlbaDc=";
    ucmHiFiConf = gistFile "HiFi-surface-laptop-ultra.conf" "sha256-0+LJTzVfPBcw/YclB7oGhAP3KQR79Pgp7YSSp8B8LTQ=";

    touchpadQuirks = gistFile "surface-laptop-ultra-touchpad.quirks" "sha256-BB3ScS29ArDeTSLvT7yJ70y8GkMz8QeC01v1xJUQufc=";
    keyRepeatRules = gistFile "71-key-repeat-surface-kbd.rules" "sha256-IpeU0TPTdZHcb4ky1sljbivfR6YfsW3jjfAqKFHqXrw=";
    kbdRepeatDelay = gistFile "kbd-repeat-delay" "sha256-rkEhh0L7r+FrEamWrTkq1up68888oJVdKpt4e8R8d+0=";
    n1xTouchpadPtp = gistFile "n1x-touchpad-ptp" "sha256-FTxxODGFQqIfXTGvpALZRU339hzU7hHRjvHKkqRezLU=";
    n1xTouchpadPtpService = gistFile "n1x-touchpad-ptp.service" "sha256-Ev0eS1yLygS+4r7FuVzHvA16L9EWS52/eS6W9BuhgsY=";
    n1xEdpBacklight = gistFile "n1x-edp-backlight" "sha256-GZ/lUQ2k98CXJVJrNFTgvmi/2624dK5/GmJZsQ5WPfQ=";
    n1xEdpBacklightService = gistFile "n1x-edp-backlight.service" "sha256-K1+WWXv8LnMvsfWy7v1tDAFm5Z5LCgUuT89KpvPW9eM=";
    surfaceKbdBacklight = gistFile "surface-kbd-backlight" "sha256-m80O5QwpwouWW+LKZLLIVl6chPd3ROGYHYn/oNZx8VU=";
    surfaceKbdBacklightService = gistFile "surface-kbd-backlight.service" "sha256-aqLLS4eDvINfivEiKuX8dMJnc2Xb6vj5LRTzR1W7jCc=";
    n1xSdwSettle = gistFile "n1x-sdw-settle" "sha256-ZEjf2yT0uS9/AWeMDjfhV1t5nFaIyNkv6hpgwCuwwc0=";
    n1xSdwSettleService = gistFile "n1x-sdw-settle.service" "sha256-RKxeXxI1vOu7OhXyHKv4bPU0FyTTuFhQ8a+lIvl3bDc=";
    n1xDkmsGuard = gistFile "n1x-dkms-guard" "sha256-xeOwgj0esfmctLkCdfboOfEeGPwKqTSc9BCy+GgYuNw=";
  };

  # --- ikegam repos --------------------------------------------------------
  surface-ultra-camera = fetchFromGitHub {
    owner = "ikegam";
    repo = "surface-ultra-camera";
    rev = "e95a23202f3a1c260f4e61476d0b0d464ebfba56";
    hash = "sha256-snGWMUS/CE9nMc0deFFIyl7akQzD9qUxFYapDIyT3SA=";
  };

  surface-ultra-misc = fetchFromGitHub {
    owner = "ikegam";
    repo = "surface-ultra-misc";
    rev = "4d00dbc292672de95de715e5e810c9860433d1a3";
    hash = "sha256-+p0vlQlfJaIJR5iA8R5EMF1DnlR90AikWG+Rb5aq/6Q=";
  };
}
