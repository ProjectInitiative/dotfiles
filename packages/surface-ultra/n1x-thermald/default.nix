# n1x-thermald — skin-temperature / SoC-power controller (Surface Laptop Ultra)
#
# From ikegam/surface-ultra-misc (thermal/), commit-pinned 2026-11-12.
#
# Linux does nothing here by default: none of the ACPI thermal zones has a
# trip point, and under sustained CPU load the SoC draws 64-68 W with Tj
# pinned at the firmware's ~98 °C. Windows' thermal policy (MPTF) keeps the
# SKIN temperature (SAM sensor VTS1 = surface_thermal temp9) at 45 °C by
# lowering the SoC's sustained power limit. This daemon reproduces that with
# the knobs Linux has:
#
#   - every 2 s, compares averaged SoC power (\_TZ.PSOC — reports mW, NOT a
#     temperature) with a budget (55 W AC / 42.5 W battery, Windows defaults)
#     and moves every CPU's scaling_max_freq in 5 % steps (floor 40 %)
#   - PI loop on skin temperature (VTS1 target 45 °C; VTS5 secondary target
#     51 °C) lowers the budget
#   - emergency: secondary skin >= 55.5 °C or battery (temp5) >= 62 °C pins
#     CPUs to minimum; 57 °C / 64 °C power off (Windows' values)
#
# Without the SSAM sensors (surface-ultra-ssam-helper's n1x_ssam_clients or
# kernel patch 0003 + sensor clients) it runs on the power budget alone.
# Fan curves stay under EC control (FAN CID 0x0b, up to 5700 RPM); the EC's
# fan response tracks skin temperature, which this daemon holds below the
# Windows targets.
{
  lib,
  python3,
  runCommand,
}:

runCommand "n1x-thermald-unstable-2026-11-12"
  {
    nativeBuildInputs = [ ];
    meta = with lib; {
      description = "Skin-temperature / SoC-power controller for the Surface Laptop Ultra (N1X) — keeps skin ≤ 45 °C via CPU frequency capping";
      platforms = [ "aarch64-linux" ];
      mainProgram = "n1x-thermald";
    };
  }
  ''
    mkdir -p $out/bin $out/lib/systemd/system
    install -Dm755 ${../../../vendor/surface-ultra/surface-ultra-misc/thermal/n1x-thermald} $out/bin/n1x-thermald
    patchShebangs $out/bin/n1x-thermald
    # Wrap: upstream relies on bare /usr/bin/python3; the daemon needs only
    # the stdlib, so the plain python3 interpreter suffices.
    install -Dm644 ${../../../vendor/surface-ultra/surface-ultra-misc/thermal/n1x-thermald.service} $out/lib/systemd/system/n1x-thermald.service
    substituteInPlace $out/lib/systemd/system/n1x-thermald.service \
      --replace-fail "ExecStart=/usr/local/bin/n1x-thermald" "ExecStart=$out/bin/n1x-thermald"
  ''
