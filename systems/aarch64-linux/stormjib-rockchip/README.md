
# NixOS Build for Rockchip RK3588/RK3582

## Project Overview

This project is a Nix-based build system for creating custom NixOS images for Rockchip RK3588/RK3582-based single-board computers (SBCs), specifically targeting a device that appears to be the Radxa E52C. It automates the process of building U-Boot, the Linux kernel, a root filesystem, and assembling them into a bootable disk image.

## File Structure

*   `default.nix`: The main NixOS configuration for the target device. It imports other modules, sets kernel parameters, and defines the overall system configuration.
*   `rockchip-sd-image.nix`: This is the core module for building the Rockchip-specific bootable image. It orchestrates the U-Boot build, kernel selection, and image assembly.
*   `uboot-build.nix`: This file defines the Nix derivations for building the U-Boot bootloader. It fetches the U-Boot source code, applies necessary patches, and builds the `idbloader.img` and `u-boot.itb` files.
*   `assemble-monolithic-image.nix`: This script takes the U-Boot binaries, the boot partition, and the rootfs partition and assembles them into a single, monolithic disk image that can be flashed to an eMMC or SD card.
*   `make-ext4.nix` & `make-fat-fs.nix`: These are helper scripts for creating the ext4 root filesystem and the FAT32 boot partition, respectively.
*   `sd-image.nix`: A more generic SD card image builder, which seems to be less used in this specific configuration in favor of the `rockchip-sd-image.nix` module.
*   `file-options.nix`: Defines Nix options for image configuration.
*   `uboot-disable-hdmi0-phy-ref.patch`: A patch file to modify the U-Boot device tree, likely to disable an HDMI port that is not used or causes issues on the target hardware.
*   `kernel/`: This directory contains pre-built kernel components (`kernel.img`, `rockchip.dtb`, `boot.scr`). These might be used for testing or as a fallback if the kernel build process is not yet fully integrated into the Nix build.

## How to Build

To build the NixOS image, you will use the `nix build` command. The specific command you provided is correct:

```bash
nix build .#nixosConfigurations.stormjib-rockchip.config.system.build.image
```

This command tells Nix to build the `image` attribute of the `stormjib-rockchip` NixOS configuration defined in your flake. The result of the build will be a symlink named `result` in your current directory, which points to the built disk image in the Nix store.

## How to Test and Install

After a successful build, the `result` symlink will point to the disk image. You can then flash this image to an SD card or eMMC.

### 1. Flashing the Image

You can use the `dd` command to write the image to your storage device. First, identify the device name of your SD card (e.g., `/dev/sdX`).

**BE EXTREMELY CAREFUL** with this step, as writing to the wrong device can result in data loss.

```bash
sudo dd if=./result of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with the correct device name for your SD card.

### 2. Flashing to eMMC with `rkdeveloptool`

For writing the image directly to the onboard eMMC storage, you'll need to use `rkdeveloptool`. This process involves putting the board into a special programming mode and then using the tool to flash the binaries.

**1. Enter Maskrom or Loader Mode**

You must first put your device into a mode where it can accept commands from `rkdeveloptool`. This is typically done by holding a specific button on the board while powering it on, or by shorting specific test points. Please refer to your board's documentation for instructions on how to enter "Maskrom mode" or "Loader mode".

Once in this mode, the device will be detectable by `rkdeveloptool`. You can verify this by running:
```bash
sudo rkdeveloptool ld
```

**2. Download the SPL Loader**

Next, you need to download a special loader binary to the device's RAM. This loader prepares the eMMC for flashing. You will need the appropriate loader file for your RK3588/RK3582 device (e.g., `rk3588_spl_loader_v1.15.113.bin`).

```bash
sudo rkdeveloptool db /path/to/your/rk3588_spl_loader.bin
```
*Replace `/path/to/your/rk3588_spl_loader.bin` with the actual path to your loader file.*

**3. Write the Image to eMMC**

After the loader is running, you can write the desired image to the eMMC. The build process generates several images inside the `result/` directory.

*   **To flash the complete NixOS system:** Use the full monolithic image. The `result` symlink points to this file.
    ```bash
    sudo rkdeveloptool wl 0 ./result
    ```

*   **To flash only the U-Boot bootloader:** If you only want to update U-Boot without touching the rest of the OS, you can flash the `uboot-only.img`.
    ```bash
    sudo rkdeveloptool wl 0 ./result/uboot-only.img
    ```

The `wl 0` command tells the tool to start writing the image at block address `0` of the eMMC. After the write operation is complete, you can reboot the device.

### 3. Debugging with Minicom

To debug the boot process, you can use a serial console. The `minicom` command you provided is the correct way to connect to the serial console of the E52C board.

```bash
sudo minicom -w -t xterm -l -R UTF-8 -D /dev/ttyUSB0 -b 1500000
```

This command will open a serial console session with the following settings:

*   `-w`: No line wrap
*   `-t xterm`: Xterm terminal type
*   `-l`: No log file
*   `-R UTF-8`: UTF-8 character encoding
*   `-D /dev/ttyUSB0`: Serial device
*   `-b 1500000`: Baud rate of 1,500,000

This will allow you to see the U-Boot and kernel boot messages and interact with the serial console.
