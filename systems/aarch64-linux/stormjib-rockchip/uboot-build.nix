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
    # Use the Collabora mirror mentioned in the instructions
    # url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/rkbin.git";
    # Fetch the default branch (e.g., main or master). Pin to a specific rev for reproducibility if needed.
    # rev = "7c35e21a8529b3758d1f051d1a5dc62aae934b2b";
    # sha256 = "03z9j7w6iaxxba0svgmdlkbk1k29swnfrc89ph5g40bmwvxqw698"; # Replace with actual hash after first fetch
    # Alternatively, use the Radxa repo if preferred (as mentioned later in the instructions for boot_merger)
    url = "https://github.com/radxa/rkbin.git";
    rev = "efaf8526fe85521ac86f4e88b0a6a6c6cf2563a1";
    hash = "sha256-/Q2P5WRHtNeqHgR/7Ckoha0RckBL7OF9jSixri7Uon8=";
    # url = "https://gitlab.collabora.com/hardware-enablement/rockchip-3588/rkbin.git";
    # rev = "7c35e21a8529b3758d1f051d1a5dc62aae934b2b";
    # sha256 = "03z9j7w6iaxxba0svgmdlkbk1k29swnfrc89ph5g40bmwvxqw698";
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
    else "${rkbin}/bin/rk35/rk3588_ddr_lp4_1866MHz_lp4x_2112MHz_lp5_2400MHz_v1.19.bin";

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
    version = "2024.10-rk3588"; # This is a branch name, consider pinning to a commit.

    src = pkgs.fetchgit {
      # radxa directly
      url = "https://github.com/radxa/u-boot.git";
      rev = "575d1a114c66ad09e0d9d9f478c993fc243f5aec";
      hash = "sha256-xvMEWX6Twj5X8AHgM67Ng7HOvF0zTBzF/Ft6TPxkZtI=";
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
      pkgs.bc # Added to resolve "bc: command not found"
      # pkgs.dtc # U-Boot should use its own dtc; add if problem persists with PATH
    ];
    buildInputs = [ pkgs.gcc ];

    ROCKCHIP_TPL = effectiveTplFile;
    BL31 = "${trusted-firmware-a}/bin/bl31.elf";
    ARCH = "arm";
    UBOOT_DEFCONFIG = "radxa-e52c-rk3588s_defconfig";

    postPatch = ''
      echo "Running patchShebangs on source tree..."
      patchShebangs .
      echo "Finished patchShebangs."
    '';

    configurePhase = ''
      runHook preConfigure
      echo "Using defconfig: ${UBOOT_DEFCONFIG}"
      make ${UBOOT_DEFCONFIG}
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      echo "Building U-Boot with ROCKCHIP_TPL=${ROCKCHIP_TPL} BL31=${BL31}"

      # Add U-Boot's script and tools directories to the PATH
      # This ensures that scripts called by make can find U-Boot's own dtc and mkimage
      export PATH=$PWD/scripts/dtc:$PWD/tools:$PATH
      echo "Updated PATH: $PATH"

      echo "### Step 1: Building U-Boot tools (including dtc, mkimage) and main binaries ###"
      # Ensure 'tools' target is built, which should build scripts/dtc/dtc and tools/mkimage.
      # Also build u-boot-nodtb.bin and u-boot.dtb as they are likely inputs for u-boot.itb.
      make -j$(nproc) tools u-boot-nodtb.bin u-boot.dtb
      # Verification
      if [ ! -f ./scripts/dtc/dtc ]; then
        echo "ERROR: U-Boot's dtc was not found in ./scripts/dtc/"
        exit 1
      fi
      if [ ! -f ./tools/mkimage ]; then
        echo "ERROR: U-Boot's mkimage was not found in ./tools/"
        exit 1
      fi
      if [ ! -f u-boot-nodtb.bin ] || [ ! -f u-boot.dtb ]; then
        echo "ERROR: u-boot-nodtb.bin or u-boot.dtb not built."
        exit 1
      fi
      echo "### Step 1 Completed: Tools and main binaries built. ###"

      echo "### Step 2: Building spl/u-boot-spl.bin ###"
      make -j$(nproc) spl/u-boot-spl.bin
      if [ ! -f spl/u-boot-spl.bin ]; then
        echo "ERROR: spl/u-boot-spl.bin was not created."
        exit 1
      fi
      echo "### Step 2 Completed: spl/u-boot-spl.bin built. ###"

      echo "### Step 3: Building u-boot.itb ###"
      # With the updated PATH, the script generating the ITS for u-boot.itb should find dtc.
      # BL31 is available as an environment variable.
      make -j$(nproc) u-boot.itb
      if [ ! -f u-boot.itb ]; then
        echo "ERROR: u-boot.itb was not created by make."
        # Provide more debug info if u-boot.itb fails
        echo "Listing contents of current directory:"
        ls -lah .
        # Fallback or exit, depending on how critical u-boot.itb is vs u-boot.img
        if [ -f u-boot.img ]; then
            echo "Note: u-boot.img exists, but u-boot.itb is the target and was not created."
            echo "Continuing to attempt idbloader.img creation..."
            # Optionally, decide here if you want to use u-boot.img later in installPhase
        else
            # If u-boot.img is also not there, then it's a more fundamental build issue for the main U-Boot.
            echo "Error: Neither u-boot.itb nor u-boot.img seem to be built. Check make output for errors."
            exit 1 
        fi
      else
        echo "### Step 3 Completed: u-boot.itb built. ###"
      fi

      echo "### Step 4: Creating idbloader.img ###"
      echo "Creating idbloader.img using ROCKCHIP_TPL=${ROCKCHIP_TPL} and spl/u-boot-spl.bin"
      ./tools/mkimage -n rk3588 -T rksd -d "${ROCKCHIP_TPL}:spl/u-boot-spl.bin" idbloader.img

      if [ ! -f idbloader.img ]; then
        echo "ERROR: idbloader.img was not created by ./tools/mkimage command."
        exit 1
      fi
      echo "### Step 4 Completed: idbloader.img created. ###"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      echo "--- Debug: Listing files in current directory ($PWD) ---"
      ls -lah .
      echo "--- Debug: Listing files in spl/ directory ---"
      ls -lah spl/
      echo "--- Debug: Listing files in tools/ directory ---"
      ls -lah tools/
      echo "--- End Debug Listing ---"

      mkdir -p $out/bin

      if [ ! -f idbloader.img ]; then
          echo "FATAL: idbloader.img not found in installPhase!"
          exit 1
      fi
      cp idbloader.img $out/bin/
      if [ ! -f u-boot.itb ]; then
          echo "FATAL: u-boot.itb not found in installPhase!"
          exit 1
      fi
      cp u-boot.itb $out/bin/

      runHook postInstall
    '';

    hardeningDisable = [ "all" ];
    dontStrip = true;
    meta = with pkgs.lib; {
      description = "U-Boot bootloader for Rockchip RK3588/RK3582"; # Updated description slightly
      homepage = "https://www.denx.de/wiki/U-Boot";
      license = licenses.gpl2Plus;
      platforms = platforms.linux;
    };
  };

in
{
  inherit rkbin trusted-firmware-a uboot-rk3588 ddrbin_tool_derivation;
}
