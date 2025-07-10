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
  # This parameter is now IGNORED because we generate the defconfig internally.
  # It's left here for reference.
  # ubootDefconfigName ? "evb-rk3588_defconfig",
  ubootDefconfigName ? "radxa_e52c_defconfig",
}:

let
  stdenv = pkgs.stdenv;

  kernel_src_unpacked = stdenv.mkDerivation {
    name = "unpacked-kernel-src";

    # Use the source of the latest kernel
    src = pkgs.linuxPackages_latest.kernel.src;

    # Only unpack the source, no need for configure, build, or check phases
    phases = [ "unpackPhase" "installPhase" ];

    installPhase = ''
      # Create the output directory
      mkdir -p $out

      # Copy the desired file from the unpacked kernel source.
      # The source is unpacked into the current directory by default.
      # The top-level directory in the unpacked source is typically 'linux-<version>'
      cp -r . $out
    '';
  };

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

  trusted-firmware-a = stdenv.mkDerivation rec {
    pname = "trusted-firmware-a-rk3588";
    version = "main";
    src = pkgs.fetchgit {
      url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/trusted-firmware-a.git";
      rev = "ed0a82a67572db4ad2e0d8fa6651944d501e941f";
      sha256 = "1pg65zjg0rcc81bzl9mn50jsjr0pm4wib8mvncis49ca5ik39jh5";
    };
    nativeBuildInputs = [ pkgs.buildPackages.gcc pkgs.buildPackages.gnumake pkgs.buildPackages.python3 ];
    buildInputs = [ pkgs.gcc ];
    PLAT = "rk3588";
    buildPhase = ''
      runHook preBuild
      make PLAT=${PLAT} CC="gcc" AS="gcc -c" bl31 -j$(nproc)
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp build/${PLAT}/release/bl31/bl31.elf $out/bin/
      runHook postInstall
    '';
    hardeningDisable = [ "all" ]; dontStrip = true;
    meta = with pkgs.lib; {
      description = "Trusted Firmware-A (BL31) for Rockchip RK3588";
      homepage = "https://www.trustedfirmware.org/";
      license = licenses.bsd3;
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
      pkgs.gnutls
      pkgs.ubootTools
      pkgs.buildPackages.xxd
    ];
    buildInputs = [ pkgs.gcc ];

    ROCKCHIP_TPL = effectiveTplFile;
    BL31 = "${trusted-firmware-a}/bin/bl31.elf";
    ARCH = "arm";
    
    # ### FIXED: Define the new custom defconfig name ###
    UBOOT_DEFCONFIG = ubootDefconfigName;

    postPatch = ''
      patchShebangs .
      
      echo "--- Patching U-Boot with Radxa E52C device tree ---"
      
      local dts_files=(
        "rk3582-radxa-e52c.dts"
        "rk3588-base-pinctrl.dtsi"
        "rk3588-extra-pinctrl.dtsi"
        "rk3588.dtsi"
      )
      
      # FIXED: Copy files to the non-standard path this U-Boot fork expects.
      local dts_dest_dir="dts/upstream/src/arm64/rockchip"
      mkdir -p ''${dts_dest_dir}

      for f in "''${dts_files[@]}"; do
        echo "Copying ''${f} to ''${dts_dest_dir}/''${f}"
        cp -v "${kernel_src_unpacked}/arch/arm64/boot/dts/rockchip/''${f}" "''${dts_dest_dir}/''${f}"
      done

      echo "--- Creating custom defconfig for Radxa E52C ---"
      cp configs/evb-rk3588_defconfig configs/${UBOOT_DEFCONFIG}

      # Now modify the default device tree in our new defconfig.
      # IMPORTANT: The path in CONFIG_DEFAULT_DEVICE_TREE must match the location where 'make' looks for the file.
      sed -i 's|CONFIG_DEFAULT_DEVICE_TREE=.*|CONFIG_DEFAULT_DEVICE_TREE="rockchip/rk3582-radxa-e52c"|' \
        configs/${UBOOT_DEFCONFIG}

      echo "Custom defconfig created at configs/${UBOOT_DEFCONFIG}"
    '';

    configurePhase = ''
      runHook preConfigure
      # This now uses our newly created radxa_e52c_defconfig
      make ARCH=${ARCH} CROSS_COMPILE="${stdenv.cc.targetPrefix}" ${UBOOT_DEFCONFIG}
      if [ ! -f .config ]; then
        echo "Error: .config was NOT created by 'make ${UBOOT_DEFCONFIG}'."
        exit 1
      fi
      echo ".config file found. Proceeding with modifications."

      set_kconfig() {
        local key="$1"
        local value="$2"
        sed -i -e "/^''${key}=.*/d" -e "/^# ''${key} is not set/d" -e "/^#''${key}=.*/d" .config
        echo "''${key}=''${value}" >> .config
      }
      enable_kconfig() {
        set_kconfig "$1" "y"
      }

      # --- Step 1: Create the default environment text file ---
      cat > uboot-environment.txt <<'EOF'
bootdelay=2
boot_targets=mmc1 mmc0
bootcmd=run distro_bootcmd
fdt_addr_r=0x0a000000
kernel_addr_r=0x0a200000
ramdisk_addr_r=0x14000000
pxefile_addr_r=0x0d000000
scriptaddr=0x0d100000
boot_extlinux=sysboot ''${devtype} ''${devnum}:''${dev_part} any ''${scriptaddr} ''${prefix}extlinux/extlinux.conf
scan_dev_for_boot=echo Scanning ''${devtype} ''${devnum}:''${dev_part}...; for prefix in / /boot/; do if test -e ''${devtype} ''${devnum}:''${dev_part} ''${prefix}extlinux/extlinux.conf; then echo Found ''${prefix}extlinux/extlinux.conf; run boot_extlinux; echo SCRIPT FAILED: continuing...; fi; done
scan_dev_for_boot_part=part list ''${devtype} ''${devnum} -bootable devplist; for dev_part in ''${devplist}; do if test ''${dev_part} = 1; then setenv dev_part 1; if sysboot ''${devtype} ''${devnum}:''${dev_part} any ''${scriptaddr} /boot/extlinux/extlinux.conf; then echo SCRIPT EXECUTED; fi; fi; done; setenv dev_part 1; run scan_dev_for_boot
mmc_boot=if mmc dev ''${devnum}; then setenv devtype mmc; run scan_dev_for_boot_part; fi
bootcmd_mmc0=setenv devnum 0; run mmc_boot
bootcmd_mmc1=setenv devnum 1; run mmc_boot
distro_bootcmd=for target in ''${boot_targets}; do run bootcmd_''${target}; done
EOF

      # --- Step 2: Set ALL remaining Kconfig options ---
      echo "Configuring U-Boot to use the default environment file..."
      enable_kconfig "CONFIG_USE_DEFAULT_ENV_FILE"
      set_kconfig "CONFIG_DEFAULT_ENV_FILE" "\"uboot-environment.txt\""
      
      # Since we created a custom defconfig, CONFIG_DEFAULT_DEVICE_TREE is already correct.
      # We just need to align the OF_LIST and SPL_OF_LIST for binman and SPL.
      set_kconfig "CONFIG_OF_LIST" "\"rockchip/rk3582-radxa-e52c\""
      set_kconfig "CONFIG_SPL_OF_LIST" "\"rockchip/rk3582-radxa-e52c\""
      
      # Now we enable all the same features you had before.
      # This ensures we don't lose any functionality.
      enable_kconfig "CONFIG_DISTRO_DEFAULTS"
      set_kconfig "CONFIG_BOOT_TARGET_DEVICES" "\"mmc1 mmc0\""
      enable_kconfig "CONFIG_CMD_FAT"
      enable_kconfig "CONFIG_CMD_EXT4"
      enable_kconfig "CONFIG_CMD_FS_GENERIC"
      enable_kconfig "CONFIG_CMD_PART"
      enable_kconfig "CONFIG_CMD_GPT"
      enable_kconfig "CONFIG_CMD_EXTLINUX"
      enable_kconfig "CONFIG_CMD_USB_MASS_STORAGE"
      enable_kconfig "CONFIG_USB_GADGET"
      enable_kconfig "CONFIG_BLK"
      enable_kconfig "CONFIG_USB_DWC3"
      enable_kconfig "CONFIG_USB_DWC3_GADGET"
      enable_kconfig "CONFIG_USB_GADGET_DOWNLOAD"
      enable_kconfig "CONFIG_USB_FUNCTION_MASS_STORAGE"
      enable_kconfig "CONFIG_CMD_UMS"
      enable_kconfig "CONFIG_MMC"
      enable_kconfig "CONFIG_DM_MMC"
      enable_kconfig "CONFIG_MMC_DW"
      enable_kconfig "CONFIG_MMC_DW_ROCKCHIP"
      enable_kconfig "CONFIG_CMD_MMC"
      enable_kconfig "CONFIG_MMC_WRITE"
      enable_kconfig "CONFIG_DOS_PARTITION"
      enable_kconfig "CONFIG_FS_FAT"
      enable_kconfig "CONFIG_MMC_HS200_SUPPORT"
      enable_kconfig "CONFIG_SPL_LIBDISK_SUPPORT"
      enable_kconfig "CONFIG_SPL_MMC_WRITE"
      enable_kconfig "CONFIG_MMC_SDHCI"
      enable_kconfig "CONFIG_MMC_SDHCI_SDMA"
      enable_kconfig "CONFIG_MMC_SDHCI_ROCKCHIP"
      set_kconfig "CONFIG_FASTBOOT_BUF_ADDR" "0x0a000000"
      enable_kconfig "CONFIG_HUSH_PARSER"
      enable_kconfig "CONFIG_CMD_MBR"
      enable_kconfig "CONFIG_OF_LIBFDT_OVERLAY"
      enable_kconfig "CONFIG_FS_EXT4"
      enable_kconfig "CONFIG_AUTO_COMPLETE"
      enable_kconfig "CONFIG_CMD_BOOTD"
      enable_kconfig "CONFIG_CMD_EDITENV"
      enable_kconfig "CONFIG_CMD_SCRIPT"
      enable_kconfig "CONFIG_CMD_SETEXPR"
      enable_kconfig "CONFIG_CMD_MEMTEST"
      enable_kconfig "CONFIG_CMD_ECHO"
      enable_kconfig "CONFIG_CMD_SOURCE"
      enable_kconfig "CONFIG_CMD_NET"
      enable_kconfig "CONFIG_CMD_PING"
      enable_kconfig "CONFIG_CMD_DHCP"

      # --- Finalize the configuration ---
      echo "Updating U-Boot configuration with all modifications (olddefconfig)..."
      make ARCH=${ARCH} CROSS_COMPILE="${stdenv.cc.targetPrefix}" olddefconfig

      echo "Verifying final key settings in .config:"
      grep -E \
        "^CONFIG_DEFAULT_DEVICE_TREE=\"rockchip/rk3582-radxa-e52c\"" \
        .config || echo "Warning: Custom DTB not set as expected."
      runHook postConfigure
    '';

    # The postConfigure and preBuild phases are no longer needed
    # for the old EVB-specific workarounds.
    postConfigure = ''
      echo "--- Final .config content (after olddefconfig) ---"
      cat .config
      echo "--- End of .config content ---"
    '';

    preBuild = ''
      echo "Skipping preBuild patch for EVB."
    '';
    
    # buildPhase and installPhase are standard and remain unchanged.
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
      description = "U-Boot bootloader for Rockchip RK3588/RK3582 (Radxa E52C)";
      homepage = "https://www.denx.de/wiki/U-Boot";
      license = licenses.gpl2Plus;
    };
  };

in
{
  inherit rkbin trusted-firmware-a uboot-rk3588 ddrbin_tool_derivation;
  effectiveTplFile = effectiveTplFile;
}
