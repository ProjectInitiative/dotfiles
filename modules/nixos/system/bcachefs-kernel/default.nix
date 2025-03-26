# /etc/nixos/modules/custom-bcachefs.nix
{ config, lib, pkgs, namespace, ... }:

with lib;

let
  cfg = config.${namespace}.system.bcachefs-kernel;

  # Define the custom kernel package here
  linux_bcachefs = { fetchFromGitHub, buildLinux, ... } @ args:
    buildLinux (args // rec {
      version = "6.14.0-rc6-bcachefs";
      modDirVersion = "6.14.0-rc6";
      
      src = fetchFromGitHub {
        owner = "koverstreet";
        repo = "bcachefs";
        rev = cfg.branch;
        hash = cfg.sourceHash;
      };
      
      structuredExtraConfig = with lib.kernel; {
        BCACHEFS_FS = yes;
        BCACHEFS_QUOTA = yes;
        BCACHEFS_POSIX_ACL = yes;
      } // (if cfg.debug then {
        BCACHEFS_DEBUG = yes;
        BCACHEFS_TESTS = yes;
      } else {});
    });

  # Build the kernel package directly
  customKernel = pkgs.callPackage linux_bcachefs {};
  
  # Create the linuxPackages for our custom kernel
  linuxPackages_custom_bcachefs = pkgs.linuxPackagesFor customKernel;
  
  # Create a Python package for the script
  bcachefsFuaTestScript = pkgs.writeScriptBin "bcachefs-fua-test" ''
    #!/usr/bin/env python3
    import os
    import glob
    import subprocess
    import json
    from datetime import datetime

    def get_device_details(dev_path):
        print(dev_path)

        # Get the major:minor device number from the path
        dev_file = f"{dev_path}/block/dev"
        maj_min = None

        try:
            with open(dev_file, 'r') as f:
                maj_min = f.read().strip()
        except Exception as e:
            print(f"Failed to read device number: {e}")
            return {
                'dev_name': "Unknown dev_name",
                'model': "Unknown model",
                'serial': "Unknown serial"
            }

        # Run lsblk to get device information in JSON format
        try:
            cmd = ["lsblk", "-d", "-o", "MODEL,NAME,SERIAL,TYPE,UUID,MAJ:MIN", "--json"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            device_data = json.loads(result.stdout)
    
            # Find the device with matching major:minor number
            for device in device_data.get("blockdevices", []):
                if device.get("maj:min") == maj_min:
                    return {
                        'dev_name': device.get('name', "Unknown dev_name"),
                        'model': device.get('model', "Unknown model"),
                        'serial': device.get('serial', "Unknown serial")
                    }
        except Exception as e:
            print(f"Failed to get device details: {e}")

        # Default return if no match found
        return {
            'dev_name': "Unknown dev_name",
            'model': "Unknown model",
            'serial': "Unknown serial"
        }

    def list_bcachefs_devices(base_dir):
        results = []
        
        # Create output directory
        output_dir = "/tmp/bcachefs-fua-test"
        os.makedirs(output_dir, exist_ok=True)
        
        report_file = os.path.join(output_dir, f"bcachefs_fua_test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt")
        
        with open(report_file, 'w') as report:
            report.write(f"Bcachefs Read FUA Test Results - {datetime.now()}\n")
            report.write("=" * 50 + "\n\n")
            
            # Iterate over each bcachefs filesystem UUID directory
            for uuid_dir in sorted(glob.glob(os.path.join(base_dir, '*'))):
                if os.path.isdir(uuid_dir):
                    uuid = os.path.basename(uuid_dir)
                    print(f"\nFilesystem UUID: {uuid}")
                    report.write(f"Filesystem UUID: {uuid}\n")
                    report.write("-" * 50 + "\n")
                    
                    fs_results = []
                    
                    # Iterate over each dev-* directory within the UUID directory
                    for dev_dir in sorted(glob.glob(os.path.join(uuid_dir, 'dev-*'))):
                        if os.path.isdir(dev_dir):
                            dev_num = os.path.basename(dev_dir).split('-')[1]
                            print(f"\nTesting device {dev_num}:")
                            report.write(f"\nDevice {dev_num}:\n")
                            
                            device_info = get_device_details(dev_dir)
                            
                            print(f"  Device: {device_info['dev_name'] or 'unknown'}")
                            print(f"  Model: {device_info['model']}")
                            print(f"  Serial: {device_info['serial']}")
                            
                            report.write(f"  Device: {device_info['dev_name'] or 'unknown'}\n")
                            report.write(f"  Model: {device_info['model']}\n")
                            report.write(f"  Serial: {device_info['serial']}\n")
                            
                            read_fua_test_file = os.path.join(dev_dir, 'read_fua_test')
                            
                            # Read and print the content of the read_fua_test file
                            if os.path.isfile(read_fua_test_file):
                                try:
                                    with open(read_fua_test_file, 'r') as file:
                                        read_fua_test_content = file.read().strip()
                                        print(f"\n  Read FUA Test Results:")
                                        print(f"  {read_fua_test_content.replace('\n', '\n  ')}")
                                        report.write("\n  Read FUA Test Results:\n")
                                        report.write(f"  {read_fua_test_content.replace('\n', '\n  ')}\n")
                                        
                                        # Add to results
                                        device_result = device_info.copy()
                                        device_result['fua_test_result'] = read_fua_test_content
                                        fs_results.append(device_result)
                                except Exception as e:
                                    error_msg = f"Error reading test file: {str(e)}"
                                    print(f"  {error_msg}")
                                    report.write(f"  {error_msg}\n")
                            else:
                                error_msg = "Read FUA Test file not found. Make sure you're using Kent Overstreet's development branch."
                                print(f"  {error_msg}")
                                report.write(f"  {error_msg}\n")
                            
                            report.write("-" * 40 + "\n")
                    
                    # Add filesystem results
                    results.append({
                        'uuid': uuid,
                        'devices': fs_results
                    })
            
            # Summary
            report.write("\n\nSUMMARY:\n")
            report.write("=" * 50 + "\n")
            
            if not results:
                report.write("No bcachefs filesystems found or no devices support read_fua_test.\n")
                print("\nNo bcachefs filesystems found or no devices support read_fua_test.")
            else:
                for fs in results:
                    report.write(f"\nFilesystem UUID: {fs['uuid']}\n")
                    
                    if not fs['devices']:
                        report.write("  No devices with read_fua_test support found.\n")
                    else:
                        for device in fs['devices']:
                            report.write(f"  Device: {device['dev_name'] or 'unknown'}, Model: {device['model']}\n")
                            
                            # Try to extract performance values
                            try:
                                lines = device['fua_test_result'].strip().split('\n')
                                for line in lines:
                                    if ':' in line:
                                        report.write(f"    {line.strip()}\n")
                            except:
                                report.write(f"    Could not parse test results\n")
        
        print(f"\nDetailed results saved to: {report_file}")
        return results

    # Define the base directory
    base_directory = '/sys/fs/bcachefs/'

    # Call the function with the base directory
    list_bcachefs_devices(base_directory)
  '';
in {
  options.${namespace}.system.bcachefs-kernel = {
    enable = mkEnableOption "custom bcachefs kernel with read_fua_test support";
    
    branch = mkOption {
      type = types.str;
      default = "master";
      description = "Git branch or commit hash of Kent Overstreet's bcachefs repository to use";
    };
    
    sourceHash = mkOption {
      type = types.str;
      default = "sha256:0000000000000000000000000000000000000000000000000000";
      description = "SHA256 hash of the source code (replace after first build attempt)";
    };
    
    debug = mkOption {
      type = types.bool;
      default = true;
      description = "Enable bcachefs debug features";
    };
  };

  config = mkIf cfg.enable {
    # nixpkgs.overlays = [
    #   (final: prev: {
    #     linuxPackages_custom_bcachefs = 
    #       let 
    #         linux_bcachefs = { fetchFromGitHub, buildLinux, ... } @ args:
    #           buildLinux (args // rec {
    #             version = "6.12-bcachefs";
    #             modDirVersion = "6.12.0";
                
    #             src = fetchFromGitHub {
    #               owner = "koverstreet";
    #               repo = "bcachefs";
    #               rev = cfg.branch;
    #               sha256 = cfg.sourceHash;
    #             };
                
    #             structuredExtraConfig = with lib.kernel; {
    #               BCACHEFS_FS = yes;
    #               BCACHEFS_QUOTA = yes;
    #               BCACHEFS_POSIX_ACL = yes;
    #             } // (if cfg.debug then {
    #               BCACHEFS_DEBUG = yes;
    #               BCACHEFS_TESTS = yes;
    #             } else {});
    #           });
    #       in
    #       final.linuxPackagesFor (final.callPackage linux_bcachefs {});
    #   })
    # ];
    
    # Use the custom kernel
    boot.kernelPackages = mkForce linuxPackages_custom_bcachefs;
    
    # Ensure bcachefs support is enabled
    boot.supportedFilesystems = [ "bcachefs" ];
    
    # Install bcachefs tools and our test script
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      nvme-cli  # For gathering NVMe device info
      bcachefsFuaTestScript
    ];
    
    # Add a systemd service that can run the test on demand
    systemd.services.bcachefs-fua-test = {
      description = "Run bcachefs read_fua_test on all devices";
      path = [ 
        pkgs.python3 
        pkgs.nvme-cli 
        pkgs.util-linux
        bcachefsFuaTestScript
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${bcachefsFuaTestScript}/bin/bcachefs-fua-test";
        StandardOutput = "journal";
      };
    };
  };
}
