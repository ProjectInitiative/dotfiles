# Handoff: StormJib (E52C) Network Speed Investigation

## Problem Statement

The `stormjib` host (Radxa E52C / RK3582) is equipped with dual RTL8125 2.5GbE NICs but consistently negotiates at 100Mbps, whereas the `astrolabe` host (Strix Halo / x86) with the same NIC chip achieves 2.5Gbps using the same cables and switch ports.

## Findings & Diagnostics

### 1. Network Topology (Layer 2 Loop)

- **Discovery**: "Martian source" logs and aggressive port flapping were observed when both ports were connected.
- **Cause**: The Brocade (1G) and MikroTik (2.5G) switches are connected via an SFP LACP link. Plugging both `stormjib` ports into this flat network created a broadcast loop.
- **Status**: Resolved by unplugging the "WAN" cable (Brocade side). Flapping stopped, but the remaining link stayed at 100Mbps.

### 2. Software & Driver Attempts

- **Drivers**: Tested both the native kernel `r8169` and the out-of-tree `r8125`.
- **Kernel**: Updated `stormjib` to the 7.0-rc kernel to match `astrolabe`, then reverted to stable 6.18. Behavior was identical on both.
- **Interrupts**: Attempted to disable MSI-X (`enable_msix=0`) to stabilize ARM interrupt handling, but the available `r8125` driver package ignored this parameter.
- **PCIe Tuning**: Forced Gen1 and Gen2 speeds via Device Tree overlays and disabled ASPM. `lspci` confirmed a healthy bus at 5GT/s (Gen2) with zero errors, indicating the issue is not the PCIe bus itself.
- **Auto-Negotiation**: Forced 1000Mbps/Full and 2500Mbps/Full, and disabled EEE. The hardware/driver ignored these overrides and "failed safe" to 100Mbps.

### 3. Physical & Power Layer

- **Cables/Switch**: Verified working at 1G/2.5G with a laptop and `astrolabe`.
- **Power**: Switched from a PoE splitter to a dedicated 5.1V/3.1A power supply. No change in behavior.
- **The "Smoking Gun"**: `dmesg` reports: `Downshift occurred from negotiated speed 1Gbps to actual speed 100Mbps, check cabling!`. This indicates the PHY is physically failing signal integrity checks on all 4 pairs.

## Current Status

`stormjib` is currently running a "Factory Reset" configuration using the native `r8169` driver with all tuning removed. It remains stuck at 100Mbps.

## Recommendations

- **Hardware Inspection**: Check RJ45 ports for bent pins or loose solder joints.
- **Low-Level Firmware**: Investigate if the current U-Boot or Device Tree is setting incorrect voltage or clocking for the RTL8125 PHYs.
- **RMA/Replacement**: Given the E52C is failing on ports where other devices succeed, the board may have a physical signal integrity defect.
