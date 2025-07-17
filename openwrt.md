# Rock 5B OpenWrt: ASIX USB Ethernet & Realtek Wi-Fi Setup Guide (OpenWrt 24.10.0)

This guide documents the troubleshooting steps taken to get an ASIX AX88179B USB Ethernet adapter and a Realtek RTL8852BE PCIe Wi-Fi adapter working on a Rock 5B board running a development version of OpenWrt (24.10.0, kernel 6.6.73).

**Initial State:**

- Rock 5B with OpenWrt 24.10.0 (development snapshot).
- No internet connectivity on the OpenWrt device initially.
- ASIX AX88179B USB Ethernet adapter detected by `lsusb` (once installed) but no network interface created.
- Realtek RTL8852BE PCIe Wi-Fi adapter detected by `lspci` but not functional.

---

## Part 1: ASIX AX88179B USB Ethernet Adapter Setup

**Problem:** The USB Ethernet adapter (ASIX AX88179B) was physically connected, and its kernel module `kmod-usb-net-asix-ax88179` (driver `ax88179_178a`) was loaded. However, no network interface (e.g., `eth1`) was being created, and the driver did not appear to bind to the device despite it being visible in `lsusb` (VID:PID `0b95:1790`).

**A. Enabling Essential Diagnostic Tools (`lsusb`) Manually**

Since the device had no internet, `opkg` couldn't download packages. `lsusb` (provided by `usbutils`) was needed for diagnostics.

1.  **Determine OpenWrt Version & Architecture:**

    - On the Rock 5B, check:
      ```bash
      cat /etc/openwrt_release | grep DISTRIB_RELEASE
      # (e.g., DISTRIB_RELEASE='24.10.0')
      opkg print-architecture | awk '{print $2}'
      # (e.g., aarch64_generic or a target-specific one like aarch64_cortex-a76)
      ```
    - The kernel version was 6.6.73.

2.  **Locate Package Files:**
    For development builds like 24.10.0, the most reliable source for compatible packages is often the **target-specific package directory**.

    - **Primary Package Source Used:** `https://mirror-03.infra.openwrt.org/releases/24.10.0/targets/rockchip/armv8/packages/`
    - (Generic architecture paths like `.../packages/aarch64_generic/base/` and `.../packages/aarch64_generic/packages/` were also explored but the target-specific path is preferred for core compatibility.)
    - The kmods specific to the exact kernel build were found at: `https://mirror-03.infra.openwrt.org/releases/24.10.0/targets/rockchip/armv8/kmods/6.6.73-1-f35e93bc2c89b98d107e57cdea041972/`

3.  **Download Necessary Packages (for `usbutils` and general USB support):**
    The following packages were manually downloaded to a separate computer:

    - `libusb-1.0-0_*.ipk` (essential dependency)
    - `libatomic1_*.ipk` (dependency for libusb on this platform)
    - `libudev-zero_*.ipk` (dependency for usbutils)
    - `libevdev_*.ipk` (dependency for usbutils)
    - `usbids_*.ipk` (provides USB ID database for lsusb)
    - `usbutils_*.ipk` (provides `lsusb`)

    You also installed a broader range of USB kernel modules during troubleshooting. While not all were strictly needed for `lsusb` itself, this was your list:

    ```
    kmod-nls-base_*.ipk
    kmod-usb-core_*.ipk
    kmod-usb-ehci_*.ipk
    kmod-usb-net-asix-ax88179_*.ipk
    kmod-usb-net-asix_*.ipk
    kmod-usb-net-cdc-ether_*.ipk
    kmod-usb-net-cdc-mbim_*.ipk
    kmod-usb-net-cdc-ncm_*.ipk
    kmod-usb-net_*.ipk
    kmod-usb-uhci_*.ipk
    kmod-usb-wdm_*.ipk
    kmod-usb-xhci-hcd_*.ipk
    kmod-usb2_*.ipk
    kmod-usb3_*.ipk
    ```

    _Self-note for future: For basic `lsusb`, only `usbutils` and its direct library dependencies are needed. The `kmod-usb-_` modules relate to enabling USB bus types and specific device class drivers.\*

4.  **Transfer Packages to Rock 5B:**
    Files were transferred to the `/tmp/` directory on the Rock 5B. Since `scp` might not have been available initially, methods like this can be used:

    - From your computer (if `ssh` server is running on OpenWrt):
      ```bash
      # To send a file:
      cat /path/to/your/package.ipk | ssh root@<rock5b_ip> "cat > /tmp/package.ipk"
      # Or using scp if available:
      # scp /path/to/your/package.ipk root@<rock5b_ip>:/tmp/
      ```

5.  **Install Packages:**
    - SSH into the Rock 5B.
    - Navigate to `/tmp/`: `cd /tmp`
    - Install (dependencies first, or all at once if opkg can resolve locally):
      ```bash
      opkg install libatomic1_*.ipk
      opkg install libudev-zero_*.ipk
      opkg install libevdev_*.ipk
      opkg install libusb-1.0-0_*.ipk
      opkg install usbids_*.ipk
      opkg install usbutils_*.ipk
      # ... and then other kmods as you did.
      ```

**B. Troubleshooting the ASIX AX88179B Driver**

- `lsusb` then confirmed the device: `ID 0b95:1790 ASIX AX88179B`.
- The specific driver `kmod-usb-net-asix-ax88179` (providing `ax88179_178a`) was installed and loaded.
- Despite numerous attempts (checking different USB ports, direct connections, USB 2.0 vs USB 3.0, manual driver bind attempts like `echo "6-1:1.0" > /sys/bus/usb/drivers/ax88179_178a/bind`), the `ax88179_178a` driver failed to create a network interface. `dmesg` remained silent from this driver, and `lsusb -t` showed `Driver=[none]` for the device interfaces.

**C. Empirical Solution for USB Ethernet:**

- You discovered that installing `kmod-usb-net-cdc-mbim_*.ipk` (and by extension its dependencies like `kmod-usb-net-cdc-ncm` and `kmod-usb-wdm`, if they weren't already present and fully functional) resulted in a network interface (likely `eth1`) appearing for the ASIX adapter.
- **Hypothesis:** The AX88179B, in this OpenWrt 24.10.0 environment, was not being handled correctly by its specific ASIX driver. Installing the `cdc-mbim` package likely brought in or correctly initialized a broader suite of USB CDC (Communications Device Class) network drivers (`cdc_ether`, `cdc_ncm`). The AX88179B might expose a generic CDC Ethernet compatible interface that one of these drivers was able to bind to, providing functionality when the specialized driver could not. This allowed you to get internet access.

---

## Part 2: Realtek RTL8852BE PCIe Wi-Fi Adapter Setup

**Problem:** The Wi-Fi card was detected by `lspci` but no wireless interface was available.

**A. Prerequisites:**

- Internet connectivity now available on the Rock 5B (thanks to the working USB Ethernet).
- `lspci` (from `pciutils` package, install if missing: `opkg update && opkg install pciutils`) identified:
  `Network controller: Realtek Semiconductor Co., Ltd. RTL8852BE PCIe 802.11ax Wireless Network Controller`

**B. Installing Wi-Fi Driver and Firmware:**

1.  **Update package lists:**
    ```bash
    opkg update
    ```
2.  **Identify and Install Packages:**

    - Kernel Modules:
      - `kmod-rtw89-pci` (for the PCIe bus)
      - `kmod-rtw89-8852be` (specific to the RTL8852BE chip)
      - Dependencies like `kmod-rtw89-core` and `kmod-rtw89-8852b-common` should be pulled automatically.
    - Firmware:
      - `rtl8852be-firmware`
    - Authentication Support:
      - OpenWrt typically uses `wpad` (e.g., `wpad-basic-mbedtls`, `wpad-wolfssl`, or `wpad-openssl`) for Wi-Fi authentication (WPA2/3, etc.) for both AP and client modes. The full `wpa_supplicant` package is usually for more advanced EAP methods or command-line client setups; `wpad` should cover most common use cases including client mode for WAN. If `wpad` was missing or a minimal version was present, installing a more featured one might be necessary: `opkg install wpad` (this usually installs the default variant) or `opkg install wpad-wolfssl` (a common, more complete option).

    You found that you explicitly needed:

    ```bash
    opkg install kmod-rtw89-8852be # This should pull in pci, core, and common modules
    # opkg install kmod-rtw89-pci (if not pulled by the above)
    opkg install rtl8852be-firmware
    # opkg install wpad (or a specific variant like wpad-wolfssl if not already sufficient)
    ```

    _Self-note for future: You mentioned needing `wpa_supplicant`. Ensure that `wpad` (the OpenWrt default which includes supplicant functionality) is installed and sufficient. If very specific EAP types are needed for the upstream Wi-Fi, then the full `wpa_supplicant` package might be required in addition to or as a replacement for the minimal `wpad-_` variant.\*

3.  **Reboot:**
    ```bash
    reboot
    ```

**C. Verification:**

- After reboot, the Wi-Fi adapter appeared in the LuCI web portal (`Network > Wireless`).
- Check `dmesg | grep -e rtw89 -e rtw_8852be` for successful firmware loading and initialization.
- `lsmod | grep rtw89` should show `rtw89_pci`, `rtw89_core`, and `rtw_8852be` (or `rtw89_8852be`).
- `iwinfo` should list the new wireless radio.

---

## Part 3: Configuring Wi-Fi as WAN (Client/STA Mode)

With the Wi-Fi adapter detected in LuCI:

1.  Go to **Network > Wireless**.
2.  Find your RTL8852BE radio and click **"Scan"**.
3.  Select your desired upstream Wi-Fi network (SSID) and click **"Join Network"**.
4.  Enter the **Passphrase** (Wi-Fi password).
5.  Name the new interface (e.g., `wwan` or `wifi_wan`).
6.  Assign the firewall zone to **`wan`**.
7.  Click **"Submit"**, then **"Save & Apply"** on the Wireless page.
8.  Go to **Network > Interfaces**.
9.  Edit the newly created `WWAN` interface (or whatever you named it).
    - **Protocol:** Set to **"DHCP client"**.
    - **Device:** Ensure it's linked to your Wi-Fi client connection.
    - **Firewall Settings:** Ensure it's assigned to the **`wan`** zone.
10. Click **"Save"**, then go back to Interfaces and click **"Save & Apply"**.

The `WWAN` interface should then connect to your upstream Wi-Fi and obtain an IP address, providing internet to your Rock 5B.

---

## Future Setup Notes & Lessons Learned:

- **Development Builds (OpenWrt 24.10.0):** Be prepared for quirks. Drivers for newer hardware or specific revisions (like AX88179**B**) might not be perfectly stable or may behave unexpectedly.
- **Package Sources:** For development/snapshot builds, using the **target-specific package directory** (`releases/<version>/targets/<target>/<subtarget>/packages/`) is generally more reliable for ensuring ABI compatibility and complete dependency sets than using the generic architecture package directories.
- **USB Ethernet (ASIX AX88179B):**
  - The dedicated `kmod-usb-net-asix-ax88179` driver _should_ be the one to work. The fact it didn't, and that `kmod-usb-net-cdc-mbim` provided a workaround, is unusual and might indicate a bug in the ASIX driver for this kernel/hardware or a very specific way the AX88179B presents itself that the CDC drivers could handle more generically.
  - For a fresh setup, always try `kmod-usb-net-asix-ax88179` first. If it fails to create an interface despite `lsusb` seeing the device, the `kmod-usb-net-cdc-mbim` (and ensuring `kmod-usb-net-cdc-ether` and `kmod-usb-net-cdc-ncm` are present) could be a fallback.
- **Wi-Fi (Realtek RTL8852BE):**
  - The `rtw89` driver family is correct (`kmod-rtw89-pci`, `kmod-rtw89-8852be`).
  - Matching `rtl8852be-firmware` is essential.
  - Ensure a suitable `wpad` package is installed for WPA2/3 client authentication.
- **Manual Package Installation:**
  - Always determine exact OpenWrt version and architecture first.
  - Download all known dependencies. `opkg` can sometimes struggle with complex local dependencies if not all are provided or if there are version conflicts not obvious from the filenames.
  - Transfer using `scp` or `ssh ... "cat > /tmp/file" < /local/file`.
- **Key Troubleshooting Commands:**
  - `dmesg` (full output after relevant action or boot)
  - `logread -f` (live log)
  - `ip a` (check interfaces)
  - `lsusb` / `lsusb -t` (check USB devices and drivers)
  - `lspci` / `lspci -v` / `lspci -k` (check PCI devices and drivers)
  - `iwinfo` (check Wi-Fi status)
  - `lsmod` (check loaded kernel modules)
  - `opkg list-installed` (check installed packages)
  - `cat /etc/config/network` and `cat /etc/config/wireless` (review configurations)

This setup required persistence, but you successfully navigated issues with both a development OpenWrt release and specific hardware.
