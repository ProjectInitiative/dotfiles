#!/usr/bin/env python3
"""
Bcachefs Read FUA Test Script

This script checks bcachefs filesystems for read_fua_test support
and collects the test results for all devices in the filesystem.
It requires Kent Overstreet's development branch of bcachefs.
"""

import os
import glob
import subprocess
import json
import argparse
from datetime import datetime
import sys

def get_device_details(dev_path):
    """
    Get device details from a bcachefs device path using lsblk.
    
    Args:
        dev_path: Path to the device in /sys/fs/bcachefs/*/dev-*
        
    Returns:
        Dict with device name, model, and serial
    """
    print(f"Examining device: {dev_path}")

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

def list_bcachefs_devices(base_dir, output_path=None):
    """
    List all bcachefs devices and their read_fua_test results.
    
    Args:
        base_dir: Base directory for bcachefs (/sys/fs/bcachefs)
        output_path: Path to save the report (optional)
        
    Returns:
        List of results by filesystem
    """
    results = []
    
    # Create output directory if specified
    output_dir = "/tmp/bcachefs-fua-test"
    if output_path:
        output_dir = os.path.dirname(output_path)
        
    if not output_path:
        output_path = os.path.join(output_dir, f"bcachefs_fua_test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt")
        os.makedirs(output_dir, exist_ok=True)
    
    with open(output_path, 'w') as report:
        report.write(f"Bcachefs Read FUA Test Results - {datetime.now()}\n")
        report.write("=" * 50 + "\n\n")
        
        # Iterate over each bcachefs filesystem UUID directory
        for uuid_dir in sorted(glob.glob(os.path.join(base_dir, '*'))):
            if os.path.isdir(uuid_dir) and not os.path.basename(uuid_dir) == "by-uuid":
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
    
    print(f"\nDetailed results saved to: {output_path}")
    return results

def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(description="Test bcachefs read FUA support on all devices")
    parser.add_argument("--output", "-o", help="Output file for report")
    parser.add_argument("--json", "-j", action="store_true", help="Output results in JSON format")
    parser.add_argument("--path", "-p", default="/sys/fs/bcachefs/", 
                        help="Base directory for bcachefs (default: /sys/fs/bcachefs/)")
    args = parser.parse_args()
    
    # Define the base directory
    base_directory = args.path
    
    if not os.path.exists(base_directory):
        print(f"Error: bcachefs path {base_directory} does not exist!")
        sys.exit(1)
    
    # Get results
    results = list_bcachefs_devices(base_directory, args.output)
    
    # Output JSON if requested
    if args.json:
        if results:
            print(json.dumps(results, indent=2))
        else:
            print(json.dumps({"error": "No bcachefs filesystems found"}))

if __name__ == "__main__":
    main()
