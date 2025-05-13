# uboot-build.nix
# Nix derivations to fetch/build U-Boot prerequisites for Rockchip RK3588.
# Based on Collabora instructions: https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot
{
  pkgs,
  # ### ADDED: Optional path to a custom TPL file you generate
  customTplFile ? null,
  # ### ADDED: Optional path to a ddrbin_param.txt file if you want Nix to try and generate the TPL
  # ### This is EXPERIMENTAL and you'll likely need to adjust ddrbin_tool_derivation
  ddrParamFile ? null,
}:

let
  stdenv = pkgs.stdenv;

  rkbin = pkgs.fetchgit {
    url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/rkbin.git";
    rev = "7c35e21a8529b3758d1f051d1a5dc62aae934b2b";
    sha256 = "03z9j7w6iaxxba0svgmdlkbk1k29swnfrc89ph5g40bmwvxqw698";
  };

  # ### ADDED: Derivation to generate DDR TPL using ddrbin_tool.py (if ddrParamFile is provided)
  # ### This is a basic structure. You might need to install ddrbin_tool.py dependencies if any.
  ddrbin_tool_derivation = if ddrParamFile != null then pkgs.runCommand "custom-rk3588-tpl" {
    nativeBuildInputs = [ pkgs.python3 ]; # Still need python
    # Pass rkbin and ddrParamFile so Nix substitutes them into the script below
    inherit rkbin ddrParamFile; # Makes them available for interpolation below
                                # (Strictly speaking not needed if they are in scope,
                                # but good practice for clarity)
  } ''
    mkdir -p $out/bin
    echo "Running ddrbin_tool.py..."
    # Use direct Nix interpolation: ${rkbin} and ${ddrParamFile}
    echo "Using rkbin from: ${rkbin}"
    echo "Using ddr_param.txt from: ${ddrParamFile}"

    # Copy the param file using the directly interpolated path
    cp ${ddrParamFile} ./ddrbin_param.txt

    # Example command structure - THIS NEEDS TO BE VERIFIED with ddrbin_tool_user_guide.txt
    # Use direct Nix interpolation for the script path: ${rkbin}
    echo "Attempting to run: python3 ${rkbin}/tools/ddrbin_tool.py rk3588 ./ddrbin_param.txt $out/bin/generated_ddr.bin"
    python3 ${rkbin}/tools/ddrbin_tool.py rk3588 ./ddrbin_param.txt $out/bin/generated_ddr.bin

    # Fallback if the above specific command fails:
    if [ ! -f $out/bin/generated_ddr.bin ]; then
      echo "Trying alternative ddrbin_tool.py invocation based on common patterns..."
      # Adjust any fallback commands similarly if they use rkbinPath
      # Example using direct interpolation:
      # python3 ${rkbin}/tools/ddrbin_tool.py rk3588 ./ddrbin_param.txt
      # cp ./*.bin $out/bin/generated_ddr.bin

      echo "Please check ddrbin_tool.py usage and adjust the script in uboot-build.nix"
      # Consider uncommenting exit 1 if fallback is not expected to work reliably
      # exit 1
    fi

    if [ -f $out/bin/generated_ddr.bin ]; then
      echo "Custom TPL generated successfully: $out/bin/generated_ddr.bin"
    else
      echo "ERROR: Custom TPL generation failed. generated_ddr.bin not found."
      exit 1
    fi
  '' else null;

  # ### MODIFIED: Use custom TPL if provided, otherwise default.
  # ### CRITICAL: The default TPL might NOT WORK for your specific E52C RAM.
  # ### You likely need to generate your own using ddrbin_tool.py and provide its path via `customTplFile`
  # ### or by setting `ddrParamFile` to have Nix attempt generation.
  effectiveTplFile =
    if customTplFile != null then customTplFile
    else if ddrbin_tool_derivation != null then "${ddrbin_tool_derivation}/bin/generated_ddr.bin" # Adjust if tool outputs a different name
    else "${rkbin}/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.18.bin";

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
    buildInputs = [ pkgs.gcc ];
    PLAT = "rk3588";

    buildPhase = ''
      runHook preBuild
      echo "Building TF-A for PLAT=${PLAT} using CC=gcc AS=\"gcc -c\""
      make PLAT=${PLAT} CC="gcc" AS="gcc -c" bl31 -j$(nproc)
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
      platforms = platforms.linux;
    };
  };

  uboot-rk3588 = stdenv.mkDerivation rec {
    pname = "u-boot-rk3588";
    version = "2024.10-rk3588"; # This is a branch name, not a tag. Consider pinning to a commit.

    src = pkgs.fetchgit {
      # ### MODIFIED: Strongly consider using Radxa's U-Boot fork for E52C if available.
      # ### Example: url = "https://github.com/radxa/u-boot.git"; rev = "branch-for-e52c-or-rk3582";
      url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot.git";
      rev = "cbc9673f77851953e294845549d418ffe2190ef9"; # Pinned to your specified commit
      sha256 = "1a5i5w1j8q7vibc6355rpmca7xf9q8jsl568vvvn4b7b24i2qqj2";
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
      pkgs.gnutls
    ];
    buildInputs = [ pkgs.gcc ];

    # ### MODIFIED: Use the effectiveTplFile which might be custom generated
    ROCKCHIP_TPL = effectiveTplFile;
    BL31 = "${trusted-firmware-a}/bin/bl31.elf";
    ARCH = "arm";

    # ### MODIFIED: Placeholder for E52C defconfig.
    # ### CRITICAL: You MUST find the correct defconfig for the Radxa E52C for your chosen U-Boot source.
    # ### Using evb-rk3588_defconfig is a fallback and might miss E52C specific drivers/settings.
    # ### If Radxa mentioned "rk2410 profiles", check if "rk2410_defconfig" exists.
    # ### Other common patterns: "radxa_e52c_defconfig", "rock5b_rk3588_defconfig" (if E52C is similar)
    UBOOT_DEFCONFIG = "evb-rk3588_defconfig"; # Replace this with the E52C specific one!

    postPatch = ''
      echo "Running patchShebangs on source tree..."
      patchShebangs .
      echo "Finished patchShebangs."
    '';

    configurePhase = ''
      runHook preConfigure
      echo "Applying U-Boot defconfig: ${UBOOT_DEFCONFIG}"
      make ${UBOOT_DEFCONFIG}
      if [ ! -f .config ]; then
        echo "Error: .config was NOT created by 'make ${UBOOT_DEFCONFIG}'."
        exit 1
      fi
      echo ".config file found. Proceeding with modifications."

      # --- Modify .config for BOOTDELAY ---
      echo "Setting CONFIG_BOOTDELAY=2 in .config"
      sed -i '/^CONFIG_BOOTDELAY=/d' .config
      echo "CONFIG_BOOTDELAY=2" >> .config

      # --- Modify .config for UMS (USB Mass Storage) ---
      echo "Enabling UMS command and dependencies in .config..."
      echo "CONFIG_CMD_USB_MASS_STORAGE=y" >> .config
      echo "CONFIG_USB_GADGET=y" >> .config
      echo "CONFIG_BLK=y" >> .config
      echo "CONFIG_USB_DWC3=y" >> .config
      echo "CONFIG_USB_DWC3_GADGET=y" >> .config
      # echo "CONFIG_USB_DWC3_ROCKCHIP=y" >> .config # Usually enabled by rk3588 defconfigs
      echo "CONFIG_USB_GADGET_DOWNLOAD=y" >> .config
      echo "CONFIG_USB_FUNCTION_MASS_STORAGE=y" >> .config
      echo "CONFIG_CMD_UMS=y" >> .config

      # --- Add/Ensure SD/MMC Kconfig options ---
      echo "Ensuring SD/MMC Kconfig options are enabled in .config..."
      echo "CONFIG_MMC=y" >> .config
      echo "CONFIG_DM_MMC=y" >> .config
      echo "CONFIG_MMC_DW=y" >> .config
      echo "CONFIG_MMC_DW_ROCKCHIP=y" >> .config
      echo "CONFIG_CMD_MMC=y" >> .config
      echo "CONFIG_MMC_WRITE=y" >> .config
      echo "CONFIG_DOS_PARTITION=y" >> .config
      # ### MODIFIED: Use CONFIG_FS_FAT instead of CONFIG_FAT_FILESYSTEM (more common in modern U-Boot)
      echo "CONFIG_FS_FAT=y" >> .config
      echo "CONFIG_MMC_HS200_SUPPORT=y" >> .config # From your list

      # --- Pre-empt FASTBOOT_BUF_ADDR prompt ---
      echo "Providing default for CONFIG_FASTBOOT_BUF_ADDR to prevent interactive prompt"
      sed -i '/^CONFIG_FASTBOOT_BUF_ADDR=/d' .config
      echo "CONFIG_FASTBOOT_BUF_ADDR=0x0a000000" >> .config

      # --- Add Kconfigs from Radxa List ---
      echo "Adding additional Kconfigs..."
      echo "CONFIG_HUSH_PARSER=y" >> .config
      echo "CONFIG_CMD_MBR=y" >> .config
      echo "CONFIG_CMD_GPT=y" >> .config
      echo "CONFIG_OF_LIBFDT_OVERLAY=y" >> .config

      # ### ADDED: Ensure EXT4 support for boot scripts or listing files if needed from ext4
      echo "CONFIG_FS_EXT4=y" >> .config

      # ### ADDED: Useful for scripting and general U-Boot usage
      echo "CONFIG_AUTO_COMPLETE=y" >> .config
      echo "CONFIG_CMD_BOOTD=y" >> .config
      echo "CONFIG_CMD_EDITENV=y" >> .config
      echo "CONFIG_CMD_EXT4=y" >> .config
      echo "CONFIG_CMD_FS_GENERIC=y" >> .config
      echo "CONFIG_CMD_GPT=y" >> .config
      echo "CONFIG_CMD_PART=y" >> .config
      echo "CONFIG_CMD_SCRIPT=y" >> .config
      echo "CONFIG_CMD_SETEXPR=y" >> .config
      echo "CONFIG_CMD_MEMTEST=y" >> .config
      echo "CONFIG_CMD_ECHO=y" >> .config
      echo "CONFIG_CMD_SOURCE=y" >> .config
      echo "CONFIG_CMD_NET=y" >> .config
      echo "CONFIG_CMD_PING=y" >> .config
      echo "CONFIG_CMD_DHCP=y" >> .config
      # echo "CONFIG_CMD_TFTPPUT=y" >> .config # If you need to upload files from U-Boot
      echo "CONFIG_CMD_EXTLINUX=y" >> .config
      echo "CONFIG_BOOTCOMMAND=\"run distro_bootcmd\"" >> .config
      echo "CONFIG_DISTRO_DEFAULTS=y" >> .config

      # Ensure these are removed first to avoid duplicates if they were set by sed above
      # Then append them to be sure they are set
      sed -i '/^CONFIG_CMD_USB_MASS_STORAGE=/d' .config; echo "CONFIG_CMD_USB_MASS_STORAGE=y" >> .config
      sed -i '/^CONFIG_USB_GADGET=/d' .config; echo "CONFIG_USB_GADGET=y" >> .config
      sed -i '/^CONFIG_BLK=/d' .config; echo "CONFIG_BLK=y" >> .config
      sed -i '/^CONFIG_USB_DWC3=/d' .config; echo "CONFIG_USB_DWC3=y" >> .config
      sed -i '/^CONFIG_USB_DWC3_GADGET=/d' .config; echo "CONFIG_USB_DWC3_GADGET=y" >> .config
      sed -i '/^CONFIG_USB_GADGET_DOWNLOAD=/d' .config; echo "CONFIG_USB_GADGET_DOWNLOAD=y" >> .config
      sed -i '/^CONFIG_USB_FUNCTION_MASS_STORAGE=/d' .config; echo "CONFIG_USB_FUNCTION_MASS_STORAGE=y" >> .config
      sed -i '/^CONFIG_CMD_UMS=/d' .config; echo "CONFIG_CMD_UMS=y" >> .config
      sed -i '/^CONFIG_MMC=/d' .config; echo "CONFIG_MMC=y" >> .config
      sed -i '/^CONFIG_DM_MMC=/d' .config; echo "CONFIG_DM_MMC=y" >> .config
      sed -i '/^CONFIG_MMC_DW=/d' .config; echo "CONFIG_MMC_DW=y" >> .config
      sed -i '/^CONFIG_MMC_DW_ROCKCHIP=/d' .config; echo "CONFIG_MMC_DW_ROCKCHIP=y" >> .config
      sed -i '/^CONFIG_CMD_MMC=/d' .config; echo "CONFIG_CMD_MMC=y" >> .config
      sed -i '/^CONFIG_MMC_WRITE=/d' .config; echo "CONFIG_MMC_WRITE=y" >> .config
      sed -i '/^CONFIG_DOS_PARTITION=/d' .config; echo "CONFIG_DOS_PARTITION=y" >> .config
      sed -i '/^CONFIG_FS_FAT=/d' .config; echo "CONFIG_FS_FAT=y" >> .config
      sed -i '/^CONFIG_MMC_HS200_SUPPORT=/d' .config; echo "CONFIG_MMC_HS200_SUPPORT=y" >> .config
      sed -i '/^CONFIG_HUSH_PARSER=/d' .config; echo "CONFIG_HUSH_PARSER=y" >> .config
      sed -i '/^CONFIG_CMD_MBR=/d' .config; echo "CONFIG_CMD_MBR=y" >> .config
      # CONFIG_CMD_GPT is already above
      sed -i '/^CONFIG_OF_LIBFDT_OVERLAY=/d' .config; echo "CONFIG_OF_LIBFDT_OVERLAY=y" >> .config
      sed -i '/^CONFIG_FS_EXT4=/d' .config; echo "CONFIG_FS_EXT4=y" >> .config
      sed -i '/^CONFIG_AUTO_COMPLETE=/d' .config; echo "CONFIG_AUTO_COMPLETE=y" >> .config
      sed -i '/^CONFIG_CMD_BOOTD=/d' .config; echo "CONFIG_CMD_BOOTD=y" >> .config
      sed -i '/^CONFIG_CMD_EDITENV=/d' .config; echo "CONFIG_CMD_EDITENV=y" >> .config
      sed -i '/^CONFIG_CMD_EXT4=/d' .config; echo "CONFIG_CMD_EXT4=y" >> .config
      sed -i '/^CONFIG_CMD_FS_GENERIC=/d' .config; echo "CONFIG_CMD_FS_GENERIC=y" >> .config
      # CONFIG_CMD_GPT is already above
      sed -i '/^CONFIG_CMD_PART=/d' .config; echo "CONFIG_CMD_PART=y" >> .config
      sed -i '/^CONFIG_CMD_SCRIPT=/d' .config; echo "CONFIG_CMD_SCRIPT=y" >> .config
      sed -i '/^CONFIG_CMD_SETEXPR=/d' .config; echo "CONFIG_CMD_SETEXPR=y" >> .config
      sed -i '/^CONFIG_CMD_MEMTEST=/d' .config; echo "CONFIG_CMD_MEMTEST=y" >> .config
      sed -i '/^CONFIG_CMD_ECHO=/d' .config; echo "CONFIG_CMD_ECHO=y" >> .config
      sed -i '/^CONFIG_CMD_SOURCE=/d' .config; echo "CONFIG_CMD_SOURCE=y" >> .config
      sed -i '/^CONFIG_CMD_NET=/d' .config; echo "CONFIG_CMD_NET=y" >> .config
      sed -i '/^CONFIG_CMD_PING=/d' .config; echo "CONFIG_CMD_PING=y" >> .config
      sed -i '/^CONFIG_CMD_DHCP=/d' .config; echo "CONFIG_CMD_DHCP=y" >> .config
      sed -i '/^CONFIG_CMD_EXTLINUX=/d' .config; echo "CONFIG_CMD_EXTLINUX=y" >> .config
      sed -i '/^CONFIG_BOOTCOMMAND=/d' .config; echo "CONFIG_BOOTCOMMAND=\"run distro_bootcmd\"" >> .config # Ensure quoted
      sed -i '/^CONFIG_DISTRO_DEFAULTS=/d' .config; echo "CONFIG_DISTRO_DEFAULTS=y" >> .config

      echo "Updating U-Boot configuration with all modifications (olddefconfig)..."
      make ARCH=${ARCH} olddefconfig

      echo "Verifying final key settings in .config:"
      grep -E \
        "^CONFIG_BOOTDELAY=|^CONFIG_CMD_UMS=|^CONFIG_FS_FAT=|^CONFIG_CMD_EXTLINUX=|^CONFIG_BOOTCOMMAND=" \
        .config || echo "Warning: Some specified Kconfig settings were not found or not set as expected post-olddefconfig."
      runHook postConfigure
    '';

    preBuild = ''
      # ### MODIFIED: Only apply patch if the evb-rk3588 defconfig is used and the dts file exists
      if [ "${UBOOT_DEFCONFIG}" == "evb-rk3588_defconfig" ] && [ -f dts/upstream/src/arm64/rockchip/rk3588-evb1-v10.dts ]; then
        echo "Patching rk3588-evb1-v10.dts to remove &hdptxphy_hdmi0 for ${UBOOT_DEFCONFIG}"
        sed -i '/&hdptxphy_hdmi0 {/,/};/d' dts/upstream/src/arm64/rockchip/rk3588-evb1-v10.dts
      else
        echo "Skipping dts patch for hdptxphy_hdmi0 as UBOOT_DEFCONFIG is not evb-rk3588_defconfig or file not found."
      fi
    '';

    buildPhase = ''
      runHook preBuild
      echo "Building U-Boot with ROCKCHIP_TPL=${ROCKCHIP_TPL} BL31=${BL31}"
      make -j$(nproc)
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
      platforms = platforms.linux;
    };
  };

in
{
  inherit rkbin trusted-firmware-a uboot-rk3588 ddrbin_tool_derivation;
}
