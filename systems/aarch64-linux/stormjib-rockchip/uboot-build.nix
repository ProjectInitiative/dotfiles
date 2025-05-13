# uboot-build.nix
# Nix derivations to fetch/build U-Boot prerequisites for Rockchip RK3588.
# Based on Collabora instructions: https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot
{
  pkgs,
# , crossSystem ? { config = "aarch64-linux"; } # Target system
}:

let
  # # Cross-compilation setup
  # pkgsCross = {
  #   system = pkgs.system; # Build system (usually x86_64-linux)
  #   crossSystem = crossSystem; # Target system (aarch64-linux)
  # };

  # stdenv = pkgsCross.stdenv;
  stdenv = pkgs.stdenv;

  # --- 1. RKBin ---
  # Fetches the Rockchip binary blobs (like the TPL/DDR init blob)
  rkbin = pkgs.fetchgit {
    # Use the Collabora mirror mentioned in the instructions
    url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/rkbin.git";
    # Fetch the default branch (e.g., main or master). Pin to a specific rev for reproducibility if needed.
    rev = "7c35e21a8529b3758d1f051d1a5dc62aae934b2b";
    sha256 = "03z9j7w6iaxxba0svgmdlkbk1k29swnfrc89ph5g40bmwvxqw698"; # Replace with actual hash after first fetch
    # Alternatively, use the Radxa repo if preferred (as mentioned later in the instructions for boot_merger)
    # url = "https://github.com/radxa/rkbin.git";
    # rev = "some-commit-hash";
    # sha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };

  # --- 2. Trusted Firmware-A (TF-A) ---
  # Builds the BL31 firmware blob
  trusted-firmware-a = stdenv.mkDerivation rec {
    pname = "trusted-firmware-a-rk3588";
    version = "main"; # Adjust if using a specific tag/commit

    src = pkgs.fetchgit {
      url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/trusted-firmware-a.git";
      # Fetch the default branch. Pin to a specific rev for reproducibility if needed.
      rev = "ed0a82a67572db4ad2e0d8fa6651944d501e941f";
      sha256 = "1pg65zjg0rcc81bzl9mn50jsjr0pm4wib8mvncis49ca5ik39jh5"; # Replace with actual hash
    };

    # Build tools needed
    nativeBuildInputs = [
      pkgs.buildPackages.gcc # Native GCC for build tools if TF-A needs them
      pkgs.buildPackages.gnumake
      pkgs.buildPackages.python3
    ];

    # Cross-compilation toolchain
    buildInputs = [
      pkgs.gcc # The cross-compiler
    ];

    # Environment variables for the build
    # Need CROSS_COMPILE prefix for aarch64-linux-gnu-
    # CROSS_COMPILE = "${stdenv.cc.targetPrefix}";
    # Specify the platform
    PLAT = "rk3588";

    # # Patch phase: Aggressively modify the problematic rules in build_macros.mk
    # patchPhase = ''
    #   runHook prePatch
    #   local target_file="make_helpers/build_macros.mk"
    #   echo "Patching $target_file to use CC instead of AS for rules with '-x assembler-with-cpp'..."

    #   # 1. Remove the problematic flag from the target lines
    #   sed -i '/^\s*\$(q)\$(\$(ARCH)-as)\s.*-x assembler-with-cpp/s|-x assembler-with-cpp||g' "$target_file"
    #   # 2. Replace the assembler command $(ARCH)-as with the C compiler $(ARCH)-cc on those same lines
    #   #    Note: We rely on $(CC) implicitly adding the '-c' flag for object generation.
    #   sed -i '/^\s*\$(q)\$(\$(ARCH)-as)\s/s|\$(\$(ARCH)-as)|$($(ARCH)-cc)|g' "$target_file"

    #   echo "Checking lines 317 and 365 in $target_file after patch:"
    #   sed -n '317p;365p' "$target_file" || echo "Failed to display patched lines in patchPhase"
    #   runHook postPatch
    # '';

    buildPhase = ''
      runHook preBuild

      echo "Unsetting potentially interfering environment variables..."
      unset CFLAGS CPPFLAGS ASFLAGS LDFLAGS || true

      echo "Building TF-A for PLAT=${PLAT} using CC=gcc AS=\"gcc -c\" override"
      # Use make with V=1 for verbose logs
      # Force make to use gcc for assembling .S files via AS="gcc -c"
      # This ensures gcc preprocesses the file before calling 'as'
      # Do NOT override ASFLAGS on the command line here.
      make PLAT=${PLAT} CC="gcc" AS="gcc -c" bl31 -j$(nproc)

      runHook postBuild
    '';

    # Build phases
    # configurePhase = '' /* No configure step typically needed for TF-A */ '';
    # buildPhase = ''
    #   runHook preBuild
    #   runHook patchPhase
    #   # Unset problematic flags that might be inherited from the environment
    #   unset ASFLAGS || true
    #   unset CFLAGS || true

    #   # Use make with explicit parameters to avoid problematic flags
    #   # make CROSS_COMPILE="${stdenv.cc.targetPrefix}" \
    #   make PLAT=${PLAT} \
    #        ASFLAGS="" \
    #        V=1 \
    #        bl31
    #   # unset ASFLAGS || true
    #   # make bl31 AS="${stdenv.cc.targetPrefix}as" ASFLAGS=""
    #   runHook postBuild
    # '';

    installPhase = ''
      runHook preInstall
      # Copy the resulting bl31.elf to the output directory
      mkdir -p $out/bin
      cp build/${PLAT}/release/bl31/bl31.elf $out/bin/
      echo "Copied bl31.elf to $out/bin/"
      runHook postInstall
    '';

    # Ensure the cross-compiler is available in the build environment
    hardeningDisable = [ "all" ]; # Often needed for firmware/bootloader builds
    dontStrip = true; # Do not strip the resulting binary

    meta = with pkgs.lib; {
      description = "Trusted Firmware-A (BL31) for Rockchip RK3588";
      homepage = "https://www.trustedfirmware.org/";
      license = licenses.bsd3; # Check TF-A license
      platforms = platforms.linux; # Can be built on linux
    };
  };

  # --- 3. U-Boot ---
  # Builds U-Boot itself (idbloader.img, u-boot.itb)
  uboot-rk3588 = stdenv.mkDerivation rec {
    pname = "u-boot-rk3588";
    # Use the branch mentioned in the Collabora instructions
    version = "2024.10-rk3588";

    src = pkgs.fetchgit {
      url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/u-boot.git";
      # Pin to the specific branch mentioned
      # ref = "refs/heads/${version}";
      rev = "cbc9673f77851953e294845549d418ffe2190ef9";
      # Fetch submodules if needed (check .gitmodules in the repo)
      # fetchSubmodules = true;
      sha256 = "1a5i5w1j8q7vibc6355rpmca7xf9q8jsl568vvvn4b7b24i2qqj2"; # Replace with actual hash
    };

    # patches = [
    #   ./uboot-disable-hdmi0-phy-ref.patch
    # ];
    # patchFlags = [ "-p1" "-f" ];

    # Build tools needed by U-Boot build system
    nativeBuildInputs = [
      pkgs.buildPackages.gcc
      pkgs.buildPackages.gnumake
      pkgs.buildPackages.bison
      pkgs.buildPackages.flex
      pkgs.buildPackages.python3
      pkgs.python3Packages.setuptools
      pkgs.python3Packages.pyelftools
      pkgs.buildPackages.swig
      pkgs.buildPackages.openssl # For FIT image signing tools
      pkgs.gnutls
      # pkgs.buildPackages.device-tree-compiler # dtc
    ];

    # Cross-compilation toolchain
    buildInputs = [
      pkgs.gcc
    ];

    # Environment variables required by U-Boot build, pointing to prerequisites
    # Note: Adjust path to the TPL blob within rkbin if necessary
    ROCKCHIP_TPL = "${rkbin}/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.18.bin";
    BL31 = "${trusted-firmware-a}/bin/bl31.elf";

    # Need CROSS_COMPILE prefix for aarch64-linux-gnu-
    # CROSS_COMPILE = "${stdenv.cc.targetPrefix}";
    # Specify the architecture
    ARCH = "arm"; # U-Boot uses ARCH=arm for aarch64

    # U-Boot defconfig for the target board
    # IMPORTANT: Verify this is the correct defconfig for Radxa E52C.
    # 'rock5b-rk3588_defconfig' is used based on Collabora notes for Rock 5B.
    # You might need to find a specific one like 'radxa-e52c-rk3582_defconfig' if it exists.
    UBOOT_DEFCONFIG = "evb-rk3588_defconfig";

    # Fix shebangs after patching and before configuring/building
    postPatch = ''
      echo "Running patchShebangs on source tree..."
      patchShebangs .
      echo "Finished patchShebangs."
    '';

    # Build phases
    configurePhase = ''
      runHook preConfigure

      echo "Applying U-Boot defconfig: ${UBOOT_DEFCONFIG}"
      make ${UBOOT_DEFCONFIG}

      if [ ! -f .config ]; then
        echo "Error: .config was NOT created by 'make ${UBOOT_DEFCONFIG}'."
        echo "Listing current directory contents (-la):"
        ls -la
        if [ ! -f "configs/${UBOOT_DEFCONFIG}" ]; then
          echo "Error: Defconfig file 'configs/${UBOOT_DEFCONFIG}' also not found!"
        fi
        exit 1
      fi
      echo ".config file found. Proceeding with modifications."

      # --- Modify .config for BOOTDELAY ---
      echo "# --- BOOTDELAY Configuration ---" >> .config
      echo "Setting CONFIG_BOOTDELAY=2 in .config"
      sed -i '/^CONFIG_BOOTDELAY=/d' .config
      echo "CONFIG_BOOTDELAY=2" >> .config
      echo "# --- End BOOTDELAY Configuration ---" >> .config

      # --- Modify .config for UMS (USB Mass Storage) ---
      echo "# --- UMS (USB Mass Storage) Configuration ---" >> .config
      echo "Enabling UMS command and dependencies in .config..."

      # Core CMD support
      sed -i '/^CONFIG_CMD_USB_MASS_STORAGE=/d' .config
      echo "CONFIG_CMD_USB_MASS_STORAGE=y" >> .config

      # Core Gadget Support
      sed -i '/^CONFIG_USB_GADGET=/d' .config
      echo "CONFIG_USB_GADGET=y" >> .config

      # BLK Support
      sed -i '/^CONFIG_BLK=/d' .config
      echo "CONFIG_BLK=y" >> .config

      # USB Device Controller (UDC) for RK3588 (DWC3 is common)
      sed -i '/^CONFIG_USB_DWC3=/d' .config
      echo "CONFIG_USB_DWC3=y" >> .config
      sed -i '/^CONFIG_USB_DWC3_GADGET=/d' .config
      echo "CONFIG_USB_DWC3_GADGET=y" >> .config
      # Potentially Rockchip-specific DWC3 platform driver:
      # sed -i '/^CONFIG_USB_DWC3_ROCKCHIP=/d' .config
      # echo "CONFIG_USB_DWC3_ROCKCHIP=y" >> .config

      # USB Gadget Download Function
      sed -i '/^CONFIG_USB_GADGET_DOWNLOAD=/d' .config
      echo "CONFIG_USB_GADGET_DOWNLOAD=y" >> .config

      # USB Mass Storage Function
      sed -i '/^CONFIG_USB_FUNCTION_MASS_STORAGE=/d' .config
      echo "CONFIG_USB_FUNCTION_MASS_STORAGE=y" >> .config

      # UMS Command Line Interface
      sed -i '/^CONFIG_CMD_UMS=/d' .config
      echo "CONFIG_CMD_UMS=y" >> .config
      echo "# --- End UMS Configuration ---" >> .config

      # --- Add/Ensure SD/MMC Kconfig options ---
      echo "# --- SD/MMC Configuration ---" >> .config
      echo "Ensuring SD/MMC Kconfig options are enabled in .config..."

      sed -i '/^CONFIG_MMC=/d' .config
      echo "CONFIG_MMC=y" >> .config

      sed -i '/^CONFIG_DM_MMC=/d' .config
      echo "CONFIG_DM_MMC=y" >> .config

      sed -i '/^CONFIG_MMC_DW=/d' .config
      echo "CONFIG_MMC_DW=y" >> .config

      sed -i '/^CONFIG_MMC_DW_ROCKCHIP=/d' .config # Verify this Kconfig for your U-Boot version
      echo "CONFIG_MMC_DW_ROCKCHIP=y" >> .config

      sed -i '/^CONFIG_CMD_MMC=/d' .config
      echo "CONFIG_CMD_MMC=y" >> .config

      sed -i '/^CONFIG_MMC_WRITE=/d' .config
      echo "CONFIG_MMC_WRITE=y" >> .config

      sed -i '/^CONFIG_DOS_PARTITION=/d' .config
      echo "CONFIG_DOS_PARTITION=y" >> .config

      sed -i '/^CONFIG_FAT_FILESYSTEM=/d' .config
      echo "CONFIG_FAT_FILESYSTEM=y" >> .config

      # Optional: For booting from SD or SPL access
      # sed -i '/^CONFIG_SPL_DM_MMC=/d' .config
      # echo "CONFIG_SPL_DM_MMC=y" >> .config
      echo "# --- End SD/MMC Configuration ---" >> .config

      # --- Pre-empt FASTBOOT_BUF_ADDR prompt ---
      echo "# --- FASTBOOT Configuration ---" >> .config
      echo "Providing default for CONFIG_FASTBOOT_BUF_ADDR to prevent interactive prompt"
      sed -i '/^CONFIG_FASTBOOT_BUF_ADDR=/d' .config
      echo "CONFIG_FASTBOOT_BUF_ADDR=0x0a000000" >> .config # Example address
      echo "# --- End FASTBOOT Configuration ---" >> .config

      # --- Add Kconfigs from Radxa List ---
      echo "# --- Additional Kconfigs from Radxa List ---" >> .config

      sed -i '/^CONFIG_HUSH_PARSER=/d' .config
      echo "CONFIG_HUSH_PARSER=y" >> .config

      sed -i '/^CONFIG_CMD_MBR=/d' .config
      echo "CONFIG_CMD_MBR=y" >> .config

      sed -i '/^CONFIG_CMD_GPT=/d' .config
      echo "CONFIG_CMD_GPT=y" >> .config

      sed -i '/^CONFIG_OF_LIBFDT_OVERLAY=/d' .config
      echo "CONFIG_OF_LIBFDT_OVERLAY=y" >> .config

      sed -i '/^CONFIG_MMC_HS200_SUPPORT=/d' .config
      echo "CONFIG_MMC_HS200_SUPPORT=y" >> .config

      # Add others you deem necessary, like SPI, NVME, specific PMIC or LED support if your hardware matches
      # For example, if your Radxa E52C uses FAN53555 and you want U-Boot to control it:
      # sed -i '/^CONFIG_DM_PMIC_FAN53555=/d' .config
      # echo "CONFIG_DM_PMIC_FAN53555=y" >> .config
      # sed -i '/^CONFIG_DM_REGULATOR_FAN53555=/d' .config
      # echo "CONFIG_DM_REGULATOR_FAN53555=y" >> .config

      echo "# --- End Additional Kconfigs from Radxa List ---" >> .config

      # Optional: Add other Kconfig defaults here if 'make olddefconfig' prompts for them
      # echo "# --- Other Kconfig Defaults ---" >> .config
      # sed -i '/^CONFIG_XYZ_NEW_OPTION=/d' .config
      # echo "CONFIG_XYZ_NEW_OPTION=some_default_value" >> .config
      # echo "# --- End Other Kconfig Defaults ---" >> .config

      echo "Updating U-Boot configuration with all modifications (olddefconfig)..."
      # Pass ARCH to ensure make olddefconfig works correctly if it's sensitive to it
      make ARCH=${ARCH} olddefconfig

      echo "Verifying final key settings in .config:"
      grep -E \
        "^CONFIG_BOOTDELAY=|^CONFIG_CMD_UMS=|^CONFIG_USB_GADGET=|^CONFIG_USB_FUNCTION_MASS_STORAGE=|^CONFIG_FASTBOOT_BUF_ADDR=|^CONFIG_MMC=|^CONFIG_CMD_MMC=|^CONFIG_MMC_DW_ROCKCHIP=" \
        .config || echo "Warning: Some specified Kconfig settings were not found or not set as expected post-olddefconfig. Check .config manually."

      runHook postConfigure
    '';

    preBuild = ''
      sed -i '/&hdptxphy_hdmi0 {/,/};/d' dts/upstream/src/arm64/rockchip/rk3588-evb1-v10.dts
    '';

    buildPhase = ''
      runHook preBuild
      echo "Building U-Boot with ROCKCHIP_TPL=${ROCKCHIP_TPL} BL31=${BL31}"
      # The default 'make' target should build everything needed (idbloader.img, u-boot.itb)
      make -j$(nproc)
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      # Copy the required output binaries
      mkdir -p $out/bin
      cp idbloader.img $out/bin/
      cp u-boot.itb $out/bin/
      # Optionally copy other potentially useful files
      # cp spl/u-boot-spl.bin $out/bin/
      # cp u-boot.bin $out/bin/
      # cp u-boot.dtb $out/bin/
      echo "Copied idbloader.img and u-boot.itb to $out/bin/"
      runHook postInstall
    '';

    hardeningDisable = [ "all" ];
    dontStrip = true;

    meta = with pkgs.lib; {
      description = "U-Boot bootloader for Rockchip RK3588 (Rock 5B config)";
      homepage = "https://www.denx.de/wiki/U-Boot";
      license = licenses.gpl2Plus; # Check U-Boot license
      platforms = platforms.linux;
    };
  };

in
{
  inherit rkbin trusted-firmware-a uboot-rk3588;
  # You can potentially add derivations for rkdeveloptool or boot_merger here too if needed
}
