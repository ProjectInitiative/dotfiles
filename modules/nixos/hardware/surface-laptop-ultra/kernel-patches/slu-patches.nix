# kernel-patches — Surface Laptop Ultra (NVIDIA N1X) kernel patch set
#
# Modular boot.kernelPatches set targeting Linux 7.x (tested upstream on
# linux-omarchy 7.2.8/7.3). Sources vendored in vendor/surface-ultra/
# (gist revision 219814edf9563ba2e91f16bb0a75eea6f31cdbdb).
#
# IMPORTANT: patches 0001 and 0002 are MUTUALLY EXCLUSIVE — both fix the
# same 26 MHz vs 52 MHz UART clock mismatch for the SAM EC (NVDA0240).
# Enable exactly one:
#   - 0001 (preferred, upstreamable): 8250_mtk honours _DSD
#     "clock-frequency" / 52 MHz for NVDA0240. Staged upstream by
#     teo-casares; requires rebuilding 8250_mtk (=y).
#   - 0002 (fallback): surface_aggregator halves the ACPI baud rate for
#     NVDA0240. This is what the Omarchy DKMS package actually ships.
{
  lib,
  # Use the DKMS-style aggregator baud quirk instead of the 8250_mtk fix.
  ssamUartViaAggregator ? false,
}:

let
  allPatches = {
    "0001-8250_mtk-NVDA0240-52mhz-clock.patch" = {
      enable = !ssamUartViaAggregator;
      comment = "8250_mtk: real 52 MHz UART clock for NVDA0240 (SAM EC serial link)";
    };
    "0002-surface_aggregator-NVDA0240-baud-quirk.patch" = {
      enable = ssamUartViaAggregator;
      comment = "surface_aggregator: halve baud on NVDA0240 (alternative to 0001)";
    };
    "0003-surface_aggregator_registry-MSHW0733.patch" = {
      enable = true;
      comment = "SSAM platform hub entry for Surface Laptop Ultra (battery + AC)";
    };
    "0004-hid-multitouch-04f3-3358-mt_cls_win_8.patch" = {
      enable = true;
      comment = "Touchpad palm rejection: bind ELAN 04F3:3358 to MT_CLS_WIN_8 (HAND-WRITTEN hunk — verify against target tree)";
    };
    "0005-soundwire-mtk-surface-ultra-mach.patch" = {
      enable = true;
      comment = "SoundWire machine table entry: 2x RT1320 + RT721 on SDW0 (speakers, mic array, jack)";
    };
  };

  selected = lib.filterAttrs (_: meta: meta.enable) allPatches;
in
lib.mapAttrsToList (name: meta: {
  inherit name;
  patch = ./. + "/${name}";
  comment = meta.comment;
}) selected
