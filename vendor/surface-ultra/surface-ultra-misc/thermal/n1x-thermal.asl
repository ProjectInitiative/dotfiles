/*
 * n1x-thermal.asl - an extra ThermalZone for Linux (Surface Laptop Ultra / NVIDIA N1X)
 *
 * Takes the firmware's \_TZ.TSOC (SoC Tj; "CPU temp" = \_SB.SCTJ in Windows MPTF) as its
 * temperature and adds only passive cooling (_PSV/_PSL = ACPI Processor -> cppc_cpufreq
 * freq_qos limit) and a critical shutdown (_CRT). No existing object is changed.
 *
 * Units are 0.1 K (Linux converts with 2732 = 0 C).
 *   _PSV 3732 = 100.0 C (a safety net: acts only if the firmware's own Tj control at ~97-98 C fails)
 *   _CRT 3782 = 105.0 C
 * Loaded at runtime through acpi_configfs (n1x-thermal-ssdt.service). It could also go into
 * an initrd as kernel/firmware/acpi/n1x-thermal.aml (CONFIG_ACPI_TABLE_UPGRADE).
 */
DefinitionBlock ("", "SSDT", 2, "N1XLNX", "N1XTHRM", 0x00000001)
{
    External (\_TZ.TSOC._TMP, MethodObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU0, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU1, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU2, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU3, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU4, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU5, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU6, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU7, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU8, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU0.CPU9, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU0, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU1, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU2, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU3, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU4, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU5, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU6, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU7, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU8, DeviceObj)
    External (\_SB.SYSM.PKG0.CLU1.CPU9, DeviceObj)

    Scope (\_TZ)
    {
        ThermalZone (NXTJ)
        {
            Name (_STR, Unicode ("N1X SoC Tj (Linux policy)"))
            Name (_TZP, 10)     // poll every 1.0 s (required: no notifications)
            Name (_TSP, 10)     // sampling while passive cooling: 1.0 s
            Name (_TC1, 1)
            Name (_TC2, 2)
            Method (_TMP, 0, Serialized)
            {
                Return (\_TZ.TSOC._TMP ())
            }
            Method (_PSV, 0, NotSerialized)
            {
                Return (3732)
            }
            Method (_CRT, 0, NotSerialized)
            {
                Return (3782)
            }
            Name (_PSL, Package (20)
            {
                \_SB.SYSM.PKG0.CLU0.CPU0,
                \_SB.SYSM.PKG0.CLU0.CPU1,
                \_SB.SYSM.PKG0.CLU0.CPU2,
                \_SB.SYSM.PKG0.CLU0.CPU3,
                \_SB.SYSM.PKG0.CLU0.CPU4,
                \_SB.SYSM.PKG0.CLU0.CPU5,
                \_SB.SYSM.PKG0.CLU0.CPU6,
                \_SB.SYSM.PKG0.CLU0.CPU7,
                \_SB.SYSM.PKG0.CLU0.CPU8,
                \_SB.SYSM.PKG0.CLU0.CPU9,
                \_SB.SYSM.PKG0.CLU1.CPU0,
                \_SB.SYSM.PKG0.CLU1.CPU1,
                \_SB.SYSM.PKG0.CLU1.CPU2,
                \_SB.SYSM.PKG0.CLU1.CPU3,
                \_SB.SYSM.PKG0.CLU1.CPU4,
                \_SB.SYSM.PKG0.CLU1.CPU5,
                \_SB.SYSM.PKG0.CLU1.CPU6,
                \_SB.SYSM.PKG0.CLU1.CPU7,
                \_SB.SYSM.PKG0.CLU1.CPU8,
                \_SB.SYSM.PKG0.CLU1.CPU9
            })
        }
    }
}
