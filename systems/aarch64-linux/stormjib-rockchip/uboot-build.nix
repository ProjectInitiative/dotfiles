# uboot-build.nix
# Nix derivations to fetch/build U-Boot prerequisites for Rockchip RK3588.
# Based on Collabora instructions: https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot
{
  pkgs,
  customTplFile ? null,
  ddrParamFile ? null,
  # ### Parameters for U-Boot source and defconfig ###
  ubootGitUrl ? "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot.git",
  ubootGitRev ? "cbc9673f77851953e294845549d418ffe2190ef9",
  ubootGitSha256 ? "1a5i5w1j8q7vibc6355rpmca7xf9q8jsl568vvvn4b7b24i2qqj2",
  # ### CRITICAL: This should be the E52C specific one if you switch to Radxa's U-Boot
  # ### e.g., "rk3588s_radxa_e52c_defconfig"
  ubootDefconfigName ? "evb-rk3588_defconfig",
}:

let
  stdenv = pkgs.stdenv;

  rkbin = pkgs.fetchgit {
    url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/rkbin.git";
    rev = "7c35e21a8529b3758d1f051d1a5dc62aae934b2b";
    sha256 = "03z9j7w6iaxxba0svgmdlkbk1k29swnfrc89ph5g40bmwvxqw698";
  };

  ddrbin_tool_derivation = if ddrParamFile != null then pkgs.runCommand "custom-rk3588-tpl" {
    nativeBuildInputs = [ pkgs.python3 ];
    inherit rkbin ddrParamFile;
  } ''
    mkdir -p $out/bin
    echo "Running ddrbin_tool.py..."
    echo "Using rkbin from: ${rkbin}"
    echo "Using ddr_param.txt from: ${ddrParamFile}"

    cp ${ddrParamFile} ./ddrbin_param.txt

    echo "Attempting to run: python3 ${rkbin}/tools/ddrbin_tool.py rk3588 ./ddrbin_param.txt $out/bin/generated_ddr.bin"
    python3 ${rkbin}/tools/ddrbin_tool.py rk3588 ./ddrbin_param.txt $out/bin/generated_ddr.bin

    if [ ! -f $out/bin/generated_ddr.bin ]; then
      echo "ERROR: Custom TPL generation failed. generated_ddr.bin not found."
      echo "Please check ddrbin_tool.py usage and adjust the script."
      exit 1
    fi
    echo "Custom TPL generated successfully: $out/bin/generated_ddr.bin"
  '' else null;

  effectiveTplFile =
    if customTplFile != null then customTplFile
    else if ddrbin_tool_derivation != null then "${ddrbin_tool_derivation}/bin/generated_ddr.bin"
    else "${rkbin}/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.18.bin";

  # ### Reverted trusted-firmware-a to its original state from your first post ###
  trusted-firmware-a = stdenv.mkDerivation rec {
    pname = "trusted-firmware-a-rk3588";
    version = "main";

    src = pkgs.fetchgit {
      url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/trusted-firmware-a.git";
      rev = "ed0a82a67572db4ad2e0d8fa6651944d501e941f";
      sha256 = "1pg65zjg0rcc81bzl9mn50jsjr0pm4wib8mvncis49ca5ik39jh5";
    };

    nativeBuildInputs = [
      pkgs.buildPackages.gcc
      pkgs.buildPackages.gnumake
      pkgs.buildPackages.python3
    ];
    buildInputs = [ pkgs.gcc ]; # Original
    PLAT = "rk3588";

    buildPhase = ''
      runHook preBuild
      echo "Building TF-A for PLAT=${PLAT} using CC=gcc AS=\"gcc -c\""
      make PLAT=${PLAT} CC="gcc" AS="gcc -c" bl31 -j$(nproc) # Original
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp build/${PLAT}/release/bl31/bl31.elf $out/bin/
      echo "Copied bl31.elf to $out/bin/"
      runHook postInstall
    '';
    hardeningDisable = [ "all" ];
    dontStrip = true;
    meta = with pkgs.lib; {
      description = "Trusted Firmware-A (BL31) for Rockchip RK3588";
      homepage = "https://www.trustedfirmware.org/";
      license = licenses.bsd3;
      # platforms = platforms.linux; # Original
    };
  };

  uboot-rk3588 = stdenv.mkDerivation rec {
    pname = "u-boot-rk3588";
    version = "custom-${builtins.substring 0 7 ubootGitRev}";

    src = pkgs.fetchgit {
      url = ubootGitUrl;
      rev = ubootGitRev;
      sha256 = ubootGitSha256;
    };

    nativeBuildInputs = [
      pkgs.buildPackages.gcc
      pkgs.buildPackages.gnumake
      pkgs.buildPackages.bison
      pkgs.buildPackages.flex
      pkgs.buildPackages.python3
      pkgs.python3Packages.setuptools
      pkgs.python3Packages.pyelftools
      pkgs.buildPackages.swig
      pkgs.buildPackages.openssl
      pkgs.gnutls # Restored from your original uboot-build.nix
      pkgs.ubootTools
      pkgs.buildPackages.xxd
    ];
    buildInputs = [ pkgs.gcc ]; # Restored from your original uboot-build.nix

    ROCKCHIP_TPL = effectiveTplFile;
    BL31 = "${trusted-firmware-a}/bin/bl31.elf";
    ARCH = "arm";
    # CROSS_COMPILE is automatically set by Nix's stdenv for cross-compilation.
    # We pass it explicitly to make for clarity and robustness.

    UBOOT_DEFCONFIG = ubootDefconfigName;

    postPatch = ''
      echo "Running patchShebangs on source tree..."
      patchShebangs .
      echo "Finished patchShebangs."
    '';

    configurePhase = ''
      runHook preConfigure
      echo "Applying U-Boot defconfig: ${UBOOT_DEFCONFIG}"
      make ARCH=${ARCH} CROSS_COMPILE="${stdenv.cc.targetPrefix}" ${UBOOT_DEFCONFIG}
      if [ ! -f .config ]; then
        echo "Error: .config was NOT created by 'make ${UBOOT_DEFCONFIG}'."
        exit 1
      fi
      echo ".config file found. Proceeding with modifications."

      # Helper function to add/replace a Kconfig option
      # Ensures the key is not duplicated and sets the desired value
      set_kconfig() {
        local key="$1"
        local value="$2"

        # Remove existing lines for this key (commented, unset, or set)
        # 1. Remove lines like 'CONFIG_KEY=...'
        sed -i "/^''${key}=.*/d" .config
        # 2. Remove lines like '# CONFIG_KEY is not set'
        sed -i "/^# ''${key} is not set/d" .config
        # 3. Remove lines like '#CONFIG_KEY=...' (no space after #)
        sed -i "/^#''${key}=.*/d" .config

        # Add the new line
        echo "''${key}=''${value}" >> .config
      }
      # Helper function to ensure a Kconfig option is 'y'
      enable_kconfig() {
        set_kconfig "$1" "y"
      }

            # --- Step 1: Create the default environment file ---
      # This is the modern, robust way to set the environment.
      # It avoids all shell quoting and build system overwrite issues.
      # The 'EOF' is quoted to prevent the shell from expanding variables.
      cat > uboot-environment.txt <<'EOF'
bootdelay=2
boot_targets=mmc1 mmc0
bootcmd=run distro_bootcmd

# --- Memory Addresses ---
fdt_addr_r=0x0a000000
kernel_addr_r=0x0a200000
ramdisk_addr_r=0x14000000
pxefile_addr_r=0x0d000000
scriptaddr=0x0d100000

# --- Distro Boot Script ---
boot_extlinux=sysboot ''${devtype} ''${devnum}:''${dev_part} any ''${scriptaddr} ''${prefix}extlinux/extlinux.conf

scan_dev_for_boot=echo Scanning ''${devtype} ''${devnum}:''${dev_part}...; for prefix in / /boot/; do if test -e ''${devtype} ''${devnum}:''${dev_part} ''${prefix}extlinux/extlinux.conf; then echo Found ''${prefix}extlinux/extlinux.conf; run boot_extlinux; echo SCRIPT FAILED: continuing...; fi; done

scan_dev_for_boot_part=part list ''${devtype} ''${devnum} -bootable devplist; for dev_part in ''${devplist}; do if test ''${dev_part} = 1; then setenv dev_part 1; if sysboot ''${devtype} ''${devnum}:''${dev_part} any ''${scriptaddr} /boot/extlinux/extlinux.conf; then echo SCRIPT EXECUTED; fi; fi; done; setenv dev_part 1; run scan_dev_for_boot

mmc_boot=if mmc dev ''${devnum}; then setenv devtype mmc; run scan_dev_for_boot_part; fi
bootcmd_mmc0=setenv devnum 0; run mmc_boot
bootcmd_mmc1=setenv devnum 1; run mmc_boot

distro_bootcmd=for target in ''${boot_targets}; do run bootcmd_''${target}; done
EOF

      # --- Step 2: Set Kconfig options to use the environment file ---
      echo "Configuring U-Boot to use the default environment file..."
      enable_kconfig "CONFIG_USE_DEFAULT_ENV_FILE"
      set_kconfig "CONFIG_DEFAULT_ENV_FILE" "\"uboot-environment.txt\""
      
      # The target DTB name, relative to dts/upstream/src/arm64/ or arch/arm/dts/
      # The path for this specific U-Boot version's structure is:
      # dts/upstream/src/arm64/rockchip/rk3588s-evb1-v10.dts
      # So the Kconfig value is "rockchip/rk3588s-evb1-v10"
      local target_dt_name="rockchip/rk3588s-evb1-v10"

      echo "Setting CONFIG_DEFAULT_DEVICE_TREE to \"''${target_dt_name}\""
      set_kconfig "CONFIG_DEFAULT_DEVICE_TREE" "\"''${target_dt_name}\""

      # This tells binman which DTBs are available and which is default for FIT
      echo "Setting CONFIG_OF_LIST to \"''${target_dt_name}\""
      set_kconfig "CONFIG_OF_LIST" "\"''${target_dt_name}\""
      
      # This tells SPL which DTB to use (if it loads one from this list)
      echo "Setting CONFIG_SPL_OF_LIST to \"''${target_dt_name}\""
      set_kconfig "CONFIG_SPL_OF_LIST" "\"''${target_dt_name}\""

      # --- Generic Distro Configuration ---
      echo "Applying Generic Distro Configuration..."

      # 1. Enable the main distro boot feature
      enable_kconfig "CONFIG_DISTRO_DEFAULTS"

      # 2. Define the devices to scan for booting.
      #    This translates the BOOT_TARGET_DEVICES macro to Kconfig.
      #    We tell it to scan mmc 1 (SD card) then mmc 0 (eMMC).
      set_kconfig "CONFIG_BOOT_TARGET_DEVICES" "\"mmc1 mmc0\""

      # Ensure commands used by the distro boot process are enabled.
      enable_kconfig "CONFIG_CMD_FAT"
      enable_kconfig "CONFIG_CMD_EXT4"
      enable_kconfig "CONFIG_CMD_FS_GENERIC"
      enable_kconfig "CONFIG_CMD_PART"
      enable_kconfig "CONFIG_CMD_GPT"
      enable_kconfig "CONFIG_CMD_EXTLINUX"

      # --- Original Kconfig modifications from your first post (slightly refactored for clarity) ---
      echo "Setting common Kconfig options..."
      set_kconfig "CONFIG_BOOTDELAY" "2"

      enable_kconfig "CONFIG_CMD_USB_MASS_STORAGE"
      enable_kconfig "CONFIG_USB_GADGET"
      enable_kconfig "CONFIG_BLK"
      enable_kconfig "CONFIG_USB_DWC3"
      enable_kconfig "CONFIG_USB_DWC3_GADGET"
      # enable_kconfig "CONFIG_USB_DWC3_ROCKCHIP" # Usually enabled by rk3588 defconfigs
      enable_kconfig "CONFIG_USB_GADGET_DOWNLOAD"
      enable_kconfig "CONFIG_USB_FUNCTION_MASS_STORAGE"
      enable_kconfig "CONFIG_CMD_UMS"

      # --- Original SD/MMC Kconfig options ---
      echo "Ensuring base SD/MMC Kconfig options are enabled..."
      enable_kconfig "CONFIG_MMC"
      enable_kconfig "CONFIG_DM_MMC"
      enable_kconfig "CONFIG_MMC_DW"
      enable_kconfig "CONFIG_MMC_DW_ROCKCHIP"
      enable_kconfig "CONFIG_CMD_MMC"
      enable_kconfig "CONFIG_MMC_WRITE"
      enable_kconfig "CONFIG_DOS_PARTITION"
      enable_kconfig "CONFIG_FS_FAT" # Was CONFIG_FAT_FILESYSTEM, FS_FAT is more common now
      enable_kconfig "CONFIG_MMC_HS200_SUPPORT"

      # ### ADDED: SD Card support options based on Radxa config ###
      echo "Adding specific SD/MMC Kconfig options for enhanced SD card support..."
      enable_kconfig "CONFIG_SPL_LIBDISK_SUPPORT"    # General disk support in SPL
      enable_kconfig "CONFIG_SPL_MMC_WRITE"          # Allow SPL to write to MMC
      enable_kconfig "CONFIG_MMC_SDHCI"              # Generic SDHCI controller support
      enable_kconfig "CONFIG_MMC_SDHCI_SDMA"         # SDMA support for SDHCI
      enable_kconfig "CONFIG_MMC_SDHCI_ROCKCHIP"     # Rockchip specific SDHCI driver

      # For raw partition access if U-Boot is loaded from a raw partition on SD/eMMC
      # These come from the Radxa config for its boot scheme
      # enable_kconfig "CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION"
      # set_kconfig    "CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION" "0x1"

      # --- Pre-empt FASTBOOT_BUF_ADDR prompt ---
      set_kconfig "CONFIG_FASTBOOT_BUF_ADDR" "0x0a000000"

      # --- Kconfigs from Radxa List / Your original additions ---
      echo "Adding additional Kconfigs..."
      enable_kconfig "CONFIG_HUSH_PARSER"
      enable_kconfig "CONFIG_CMD_MBR"
      enable_kconfig "CONFIG_CMD_GPT"
      enable_kconfig "CONFIG_OF_LIBFDT_OVERLAY"
      enable_kconfig "CONFIG_FS_EXT4"
      enable_kconfig "CONFIG_AUTO_COMPLETE"
      enable_kconfig "CONFIG_CMD_BOOTD"
      enable_kconfig "CONFIG_CMD_EDITENV"
      enable_kconfig "CONFIG_CMD_EXT4"
      enable_kconfig "CONFIG_CMD_FS_GENERIC"
      # CONFIG_CMD_GPT already enabled
      enable_kconfig "CONFIG_CMD_PART"
      enable_kconfig "CONFIG_CMD_SCRIPT"
      enable_kconfig "CONFIG_CMD_SETEXPR"
      enable_kconfig "CONFIG_CMD_MEMTEST"
      enable_kconfig "CONFIG_CMD_ECHO"
      enable_kconfig "CONFIG_CMD_SOURCE"
      enable_kconfig "CONFIG_CMD_NET"
      enable_kconfig "CONFIG_CMD_PING"
      enable_kconfig "CONFIG_CMD_DHCP"
      # enable_kconfig "CONFIG_CMD_TFTPPUT" # If you need to upload files from U-Boot
      enable_kconfig "CONFIG_CMD_EXTLINUX"
      set_kconfig "CONFIG_BOOTCOMMAND" "\"run distro_bootcmd\"" # Ensure quotes
      enable_kconfig "CONFIG_DISTRO_DEFAULTS"

      # Ensure all changes are applied and dependencies resolved
      echo "Updating U-Boot configuration with all modifications (olddefconfig)..."
      make ARCH=${ARCH} CROSS_COMPILE="${stdenv.cc.targetPrefix}" olddefconfig

      echo "Verifying final key settings in .config:"
      grep -E \
        "^CONFIG_BOOTDELAY=|^CONFIG_CMD_UMS=|^CONFIG_FS_FAT=|^CONFIG_CMD_EXTLINUX=|^CONFIG_BOOTCOMMAND=|^CONFIG_MMC_SDHCI=|^CONFIG_USE_DEFAULT_ENV_FILE=y|^CONFIG_DEFAULT_ENV_FILE=" \
        .config || echo "Warning: Some specified Kconfig settings were not found or not set as expected post-olddefconfig."
      runHook postConfigure
    '';

    postConfigure = ''
      echo "--- Final .config content (after olddefconfig) ---"
      cat .config
      echo "--- End of .config content ---"
      # Make sure the rk3588s-evb1-v10.dts file is actually present in the source tree
      echo "Checking for presence of target DTS file: dts/upstream/src/arm64/rockchip/''${target_dt_name}.dts"
      if [ ! -f "dts/upstream/src/arm64/''${target_dt_name}.dts" ]; then
        echo "ERROR: Target DTS file dts/upstream/src/arm64/''${target_dt_name}.dts not found in U-Boot source!"
        # Check common alternative path too, just in case
        if [ ! -f "arch/arm/dts/''${target_dt_name}.dts" ]; then
            echo "ERROR: Target DTS file also not found in arch/arm/dts/''${target_dt_name}.dts"
        else
            echo "INFO: Target DTS file found at arch/arm/dts/''${target_dt_name}.dts"
        fi
        # exit 1 # Optionally exit if not found, to catch issues early
      else
        echo "INFO: Target DTS file dts/upstream/src/arm64/''${target_dt_name}.dts found."
      fi
    '';

    preBuild = ''
      # This patch is specific to evb-rk3588_defconfig and its DTS in Collabora's U-Boot.
      # If you switch to a Radxa defconfig (e.g., rk3588s_radxa_e52c_defconfig),
      # it will use its own DTS, and this patch will likely be IRRELEVANT or HARMFUL.
      if [ "${UBOOT_DEFCONFIG}" == "evb-rk3588_defconfig" ] && [ -f dts/upstream/src/arm64/rockchip/rk3588s-evb1-v10.dts ]; then
        echo "Patching rk3588-evb1-v10.dts to remove &hdptxphy_hdmi0 for ${UBOOT_DEFCONFIG}"
        sed -i '/&hdptxphy_hdmi0 {/,/};/d' dts/upstream/src/arm64/rockchip/rk3588-evb1-v10.dts
      else
        echo "Skipping dts patch for hdptxphy_hdmi0: UBOOT_DEFCONFIG is '${UBOOT_DEFCONFIG}' (not evb-rk3588_defconfig) or DTS file not found."
      fi
    '';

    buildPhase = ''
      runHook preBuild
      echo "Building U-Boot with ROCKCHIP_TPL=${ROCKCHIP_TPL} BL31=${BL31}"
      make ARCH=${ARCH} CROSS_COMPILE="${stdenv.cc.targetPrefix}" -j$(nproc)
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp idbloader.img $out/bin/
      cp u-boot.itb $out/bin/
      echo "Copied idbloader.img and u-boot.itb to $out/bin/"
      runHook postInstall
    '';

    hardeningDisable = [ "all" ];
    dontStrip = true;
    meta = with pkgs.lib; {
      description = "U-Boot bootloader for Rockchip RK3588/RK3582";
      homepage = "https://www.denx.de/wiki/U-Boot";
      license = licenses.gpl2Plus;
      # platforms = platforms.aarch64-linux; # Produces aarch64 binaries
    };
  };

in
{
  inherit rkbin trusted-firmware-a uboot-rk3588 ddrbin_tool_derivation;
  effectiveTplFile = effectiveTplFile; # Expose for potential external use
}
