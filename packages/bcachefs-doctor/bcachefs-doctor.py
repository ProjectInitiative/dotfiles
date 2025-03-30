#!/usr/bin/env python3
"""
Bcachefs Doctor

A comprehensive diagnostic and reporting tool for bcachefs filesystems.
This script collects detailed information about bcachefs configurations,
settings, and parameters to help with debugging and system analysis.

Think of it as 'neofetch' for bcachefs.
"""

import os
import sys
import glob
import json
import argparse
import subprocess
import platform
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple, Union

# ANSI color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def format_bytes(num_bytes: int) -> str:
    """
    Convert a number of bytes into a human-readable string using binary units.
    """
    num = float(num_bytes)
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']:
        if num < 1024 or unit == 'PiB':
            return f"{num:.2f} {unit}"
        num /= 1024

def run_command(cmd: List[str], timeout: int = 10) -> Dict[str, Any]:
    """
    Run a command and return its output.
    
    Args:
        cmd: Command to run as list of strings
        timeout: Command timeout in seconds
        
    Returns:
        Dictionary with stdout, stderr, and return code
    """
    result = {"stdout": "", "stderr": "", "returncode": -1, "success": False}
    
    try:
        process = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        result["stdout"] = process.stdout
        result["stderr"] = process.stderr
        result["returncode"] = process.returncode
        result["success"] = process.returncode == 0
    except subprocess.TimeoutExpired:
        result["stderr"] = f"Command timed out after {timeout} seconds"
    except Exception as e:
        result["stderr"] = f"Error executing command: {str(e)}"
        
    return result

def get_kernel_info() -> Dict[str, str]:
    """Get information about the kernel and bcachefs support."""
    info = {
        "kernel_version": platform.release(),
        "kernel_arch": platform.machine(),
        "bcachefs_supported": False,
        "bcachefs_module_loaded": False,
        "bcachefs_module_details": "",
        "bcachefs_mount_options": []
    }
    
    # Check if bcachefs filesystem type is supported
    filesystems_cmd = run_command(["cat", "/proc/filesystems"])
    if filesystems_cmd["success"]:
        if "bcachefs" in filesystems_cmd["stdout"]:
            info["bcachefs_supported"] = True
    
    # Check if bcachefs module is loaded
    modules_cmd = run_command(["lsmod"])
    if modules_cmd["success"]:
        if "bcachefs" in modules_cmd["stdout"]:
            info["bcachefs_module_loaded"] = True
            
            # Get module details
            modinfo_cmd = run_command(["modinfo", "bcachefs"])
            if modinfo_cmd["success"]:
                info["bcachefs_module_details"] = modinfo_cmd["stdout"]
    
    # Get default mount options
    mount_cmd = run_command(["mount", "-t", "bcachefs"])
    if mount_cmd["success"]:
        for line in mount_cmd["stdout"].splitlines():
            if "bcachefs" in line and "(" in line and ")" in line:
                options_part = line.split("(")[1].split(")")[0]
                info["bcachefs_mount_options"] = options_part.split(",")
    
    return info

def get_system_info() -> Dict[str, Any]:
    """Get general system information."""
    info = {
        "hostname": platform.node(),
        "os": "",
        "cpu": "",
        "memory_total": 0,
        "bcachefs_tools_version": ""
    }
    
    # Try to get OS info
    try:
        os_release_cmd = run_command(["cat", "/etc/os-release"])
        if os_release_cmd["success"]:
            for line in os_release_cmd["stdout"].splitlines():
                if line.startswith("PRETTY_NAME="):
                    info["os"] = line.split("=")[1].strip('"')
                    break
    except:
        info["os"] = f"{platform.system()} {platform.release()}"
    
    # Get CPU info
    cpu_cmd = run_command(["grep", "model name", "/proc/cpuinfo"])
    if cpu_cmd["success"] and cpu_cmd["stdout"]:
        info["cpu"] = cpu_cmd["stdout"].splitlines()[0].split(":")[1].strip()
    
    # Get memory info
    mem_cmd = run_command(["grep", "MemTotal", "/proc/meminfo"])
    if mem_cmd["success"] and mem_cmd["stdout"]:
        # Convert kB to bytes
        mem_kb = int(mem_cmd["stdout"].split()[1])
        info["memory_total"] = mem_kb * 1024
    
    # Get bcachefs-tools version
    bcachefs_version_cmd = run_command(["bcachefs", "version"])
    if bcachefs_version_cmd["success"]:
        info["bcachefs_tools_version"] = bcachefs_version_cmd["stdout"].strip()
    
    return info

def find_bcachefs_instances() -> List[str]:
    """Find all bcachefs instances in /sys/fs/bcachefs."""
    base_dir = "/sys/fs/bcachefs"
    if not os.path.exists(base_dir):
        return []
        
    return [d for d in os.listdir(base_dir) 
            if os.path.isdir(os.path.join(base_dir, d)) and d != "by-uuid"]

def get_sysfs_file_content(path: str) -> str:
    """Safely read content from a sysfs file."""
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return ""

def get_fs_devices(fs_path: str) -> List[Dict[str, Any]]:
    """Get information about all devices in a bcachefs filesystem."""
    devices = []
    
    # Find all dev-* directories
    dev_dirs = glob.glob(os.path.join(fs_path, "dev-*"))
    
    for dev_dir in dev_dirs:
        device = {"path": dev_dir}
        
        # Get device label
        label_file = os.path.join(dev_dir, "label")
        if os.path.isfile(label_file):
            device["label"] = get_sysfs_file_content(label_file)
        
        # Get block device information
        block_dir = os.path.join(dev_dir, "block")
        if os.path.isdir(block_dir):
            # Get device major:minor
            dev_file = os.path.join(block_dir, "dev")
            if os.path.isfile(dev_file):
                device["dev"] = get_sysfs_file_content(dev_file)
                
                # Use lsblk to get more device info
                if device.get("dev"):
                    cmd = ["lsblk", "-d", "-o", "NAME,MODEL,SERIAL,SIZE,TYPE,FSTYPE,UUID,VENDOR", 
                           "--json", "--nodeps"]
                    result = run_command(cmd)
                    
                    if result["success"]:
                        try:
                            lsblk_data = json.loads(result["stdout"])
                            for blk_device in lsblk_data.get("blockdevices", []):
                                # Try to match by major:minor
                                dev_path = f"/dev/{blk_device.get('name', '')}"
                                dev_cmd = run_command(["stat", "-c", "%t:%T", dev_path])
                                
                                if dev_cmd["success"] and dev_cmd["stdout"].strip() == device["dev"]:
                                    device.update({
                                        "name": blk_device.get("name", ""),
                                        "model": blk_device.get("model", ""),
                                        "serial": blk_device.get("serial", ""),
                                        "size": blk_device.get("size", ""),
                                        "type": blk_device.get("type", ""),
                                        "vendor": blk_device.get("vendor", "")
                                    })
                                    break
                        except json.JSONDecodeError:
                            pass
        
        # Get device options
        opts_dir = os.path.join(dev_dir, "options")
        if os.path.isdir(opts_dir):
            device["options"] = {}
            for opt_file in os.listdir(opts_dir):
                opt_path = os.path.join(opts_dir, opt_file)
                if os.path.isfile(opt_path):
                    device["options"][opt_file] = get_sysfs_file_content(opt_path)
        
        # Get device statistics
        stats_dir = os.path.join(dev_dir, "stats")
        if os.path.isdir(stats_dir):
            device["stats"] = {}
            for stat_file in os.listdir(stats_dir):
                stat_path = os.path.join(stats_dir, stat_file)
                if os.path.isfile(stat_path):
                    try:
                        device["stats"][stat_file] = int(get_sysfs_file_content(stat_path))
                    except ValueError:
                        device["stats"][stat_file] = get_sysfs_file_content(stat_path)
        
        # Get I/O done info
        io_file = os.path.join(dev_dir, "io_done")
        if os.path.isfile(io_file):
            device["io_done"] = parse_io_done(io_file)
        
        devices.append(device)
    
    return devices

def parse_io_done(file_path: str) -> Dict[str, Dict[str, int]]:
    """Parse an io_done file from bcachefs sysfs."""
    results = {"read": {}, "write": {}}
    current_section = None
    
    try:
        with open(file_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                    
                # Detect section headers.
                if line.lower() in ("read:", "write:"):
                    current_section = line[:-1].lower()  # remove trailing colon
                    continue

                if current_section is None:
                    continue

                # Expect lines like "metric : value"
                if ':' in line:
                    key_part, value_part = line.split(":", 1)
                    key = key_part.strip()
                    try:
                        value = int(value_part.strip())
                    except ValueError:
                        value = 0
                    results[current_section][key] = value
    except Exception:
        pass
        
    return results

def get_fs_features(fs_path: str) -> Dict[str, str]:
    """Get filesystem features from sysfs."""
    features = {}
    
    # Common feature files
    feature_files = [
        "allocation_background", "allocation_foreground", "block_size", "btree_node_size",
        "compression", "encoded_extent_max", "erasure_code", "journal_flush_delay",
        "metadata_checksum", "metadata_replicas", "quota_enabled", "version",
        "version_upgrade"
    ]
    
    for feature in feature_files:
        feature_path = os.path.join(fs_path, feature)
        if os.path.isfile(feature_path):
            features[feature] = get_sysfs_file_content(feature_path)
    
    return features

def get_mounted_filesystems() -> List[Dict[str, str]]:
    """Get information about mounted bcachefs filesystems."""
    filesystems = []
    
    # Get mounted filesystems from /proc/mounts
    try:
        with open("/proc/mounts", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 6 and parts[2] == "bcachefs":
                    fs = {
                        "device": parts[0],
                        "mountpoint": parts[1],
                        "type": parts[2],
                        "options": parts[3],
                        "dump": parts[4],
                        "pass": parts[5]
                    }
                    filesystems.append(fs)
    except Exception:
        pass
    
    return filesystems

def run_bcachefs_status(mountpoint: str = None) -> Dict[str, Any]:
    """Run bcachefs status and parse the output."""
    cmd = ["bcachefs", "status"]
    
    if mountpoint:
        cmd.append(mountpoint)
    
    result = run_command(cmd)
    if not result["success"]:
        return {"error": result["stderr"]}
    
    status_info = {"raw": result["stdout"], "parsed": {}}
    
    # Very simple parsing - could be improved
    lines = result["stdout"].splitlines()
    for line in lines:
        if ":" in line:
            key, value = line.split(":", 1)
            status_info["parsed"][key.strip()] = value.strip()
    
    return status_info

def get_fs_usage(mountpoint: str) -> Dict[str, Any]:
    """Get filesystem usage statistics."""
    usage = {}
    
    # Use df to get filesystem usage
    df_cmd = run_command(["df", "-h", mountpoint])
    if df_cmd["success"]:
        lines = df_cmd["stdout"].splitlines()
        if len(lines) >= 2:
            # Parse df header and values
            headers = lines[0].split()
            values = lines[1].split()
            
            # Pair headers with values
            for i, header in enumerate(headers):
                if i < len(values):
                    usage[header] = values[i]
    
    # Get bcachefs status for the mountpoint
    status = run_bcachefs_status(mountpoint)
    usage["bcachefs_status"] = status
    
    return usage

def process_fs_info(fs_uuid: str) -> Dict[str, Any]:
    """Process information about a single bcachefs filesystem."""
    fs_path = f"/sys/fs/bcachefs/{fs_uuid}"
    if not os.path.isdir(fs_path):
        return {"error": f"Filesystem {fs_uuid} not found"}
    
    fs_info = {
        "uuid": fs_uuid,
        "features": get_fs_features(fs_path),
        "devices": get_fs_devices(fs_path)
    }
    
    # Find mountpoint for this filesystem
    mounted_fs = get_mounted_filesystems()
    for fs in mounted_fs:
        # Check if device contains the UUID
        if fs_uuid in fs["device"] or any(fs_uuid in dev.get("label", "") 
                                         for dev in fs_info["devices"]):
            fs_info["mountpoint"] = fs["mountpoint"]
            fs_info["mount_options"] = fs["options"]
            fs_info["usage"] = get_fs_usage(fs["mountpoint"])
            break
    
    return fs_info

def format_report_text(fs_info: Dict[str, Any]) -> str:
    """Format filesystem information as a text report."""
    lines = []
    
    # Add ASCII art header (could be replaced with a proper bcachefs logo)
    lines.append(Colors.BLUE + """
 ██████╗   ██████╗ █████╗  ██████╗██╗  ██╗███████╗███████╗███████╗
 ██╔══██╗ ██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝██╔════╝██╔════╝
 ██████╔╝ ██║     ███████║██║     ███████║█████╗  █████╗  ███████╗
 ██╔══██╗ ██║     ██╔══██║██║     ██╔══██║██╔══╝  ██╔══╝  ╚════██║
 ██████╔╝ ╚██████╗██║  ██║╚██████╗██║  ██║███████╗██║     ███████║
 ╚═════╝   ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚══════╝
                                                                   
                        🚑️  DOCTOR REPORT  🚑️  
    """ + Colors.ENDC)
    
    # Add system information
    sys_info = get_system_info()
    kernel_info = get_kernel_info()
    
    lines.append(f"{Colors.BOLD}System Information:{Colors.ENDC}")
    lines.append(f"  {Colors.CYAN}Hostname:{Colors.ENDC}      {sys_info['hostname']}")
    lines.append(f"  {Colors.CYAN}OS:{Colors.ENDC}            {sys_info['os']}")
    lines.append(f"  {Colors.CYAN}Kernel:{Colors.ENDC}        {kernel_info['kernel_version']} ({kernel_info['kernel_arch']})")
    lines.append(f"  {Colors.CYAN}CPU:{Colors.ENDC}           {sys_info['cpu']}")
    lines.append(f"  {Colors.CYAN}Memory:{Colors.ENDC}        {format_bytes(sys_info['memory_total'])}")
    lines.append(f"  {Colors.CYAN}Tools Version:{Colors.ENDC} {sys_info['bcachefs_tools_version']}")
    lines.append("")
    
    # Add filesystem information
    lines.append(f"{Colors.BOLD}Filesystem Information:{Colors.ENDC}")
    lines.append(f"  {Colors.CYAN}UUID:{Colors.ENDC}          {fs_info['uuid']}")
    
    # Add mountpoint if available
    if "mountpoint" in fs_info:
        lines.append(f"  {Colors.CYAN}Mountpoint:{Colors.ENDC}    {fs_info['mountpoint']}")
        lines.append(f"  {Colors.CYAN}Mount Options:{Colors.ENDC} {fs_info.get('mount_options', 'N/A')}")
    else:
        lines.append(f"  {Colors.CYAN}Status:{Colors.ENDC}        Not Mounted")
    
    lines.append("")
    
    # Add filesystem features
    lines.append(f"{Colors.BOLD}Filesystem Features:{Colors.ENDC}")
    for feature, value in fs_info.get("features", {}).items():
        lines.append(f"  {Colors.CYAN}{feature}:{Colors.ENDC} {value}")
    lines.append("")
    
    # Add device information
    lines.append(f"{Colors.BOLD}Devices ({len(fs_info.get('devices', []))}):{Colors.ENDC}")
    for i, device in enumerate(fs_info.get("devices", []), 1):
        lines.append(f"  {Colors.YELLOW}Device #{i}:{Colors.ENDC}")
        lines.append(f"    {Colors.CYAN}Label:{Colors.ENDC}        {device.get('label', 'N/A')}")
        lines.append(f"    {Colors.CYAN}Name:{Colors.ENDC}         {device.get('name', 'N/A')}")
        lines.append(f"    {Colors.CYAN}Model:{Colors.ENDC}        {device.get('model', 'N/A')}")
        lines.append(f"    {Colors.CYAN}Serial:{Colors.ENDC}       {device.get('serial', 'N/A')}")
        lines.append(f"    {Colors.CYAN}Size:{Colors.ENDC}         {device.get('size', 'N/A')}")
        lines.append(f"    {Colors.CYAN}Type:{Colors.ENDC}         {device.get('type', 'N/A')}")
        
        # Add device options
        if "options" in device and device["options"]:
            lines.append(f"    {Colors.CYAN}Options:{Colors.ENDC}")
            for opt, val in device["options"].items():
                lines.append(f"      {opt}: {val}")
        
        # Add I/O statistics summary
        if "io_done" in device:
            lines.append(f"    {Colors.CYAN}I/O Statistics:{Colors.ENDC}")
            
            read_total = sum(device["io_done"]["read"].values())
            write_total = sum(device["io_done"]["write"].values())
            
            lines.append(f"      Read:  {format_bytes(read_total)}")
            lines.append(f"      Write: {format_bytes(write_total)}")
        
        lines.append("")
    
    # Add usage information if available
    if "usage" in fs_info:
        usage = fs_info["usage"]
        lines.append(f"{Colors.BOLD}Usage Information:{Colors.ENDC}")
        
        for key, value in usage.items():
            if key != "bcachefs_status":
                lines.append(f"  {Colors.CYAN}{key}:{Colors.ENDC} {value}")
        
        # Add bcachefs status information if available
        if "bcachefs_status" in usage and "parsed" in usage["bcachefs_status"]:
            lines.append(f"\n  {Colors.CYAN}Bcachefs Status:{Colors.ENDC}")
            for key, value in usage["bcachefs_status"]["parsed"].items():
                lines.append(f"    {key}: {value}")
    
    return "\n".join(lines)

def format_report_json(fs_info: Dict[str, Any]) -> str:
    """Format filesystem information as JSON."""
    # Add system information
    report = {
        "system": get_system_info(),
        "kernel": get_kernel_info(),
        "filesystem": fs_info,
        "generated_at": datetime.now().isoformat()
    }
    
    return json.dumps(report, indent=2)

def save_report(report: str, output_file: str) -> bool:
    """Save the report to a file."""
    try:
        with open(output_file, "w") as f:
            f.write(report)
        return True
    except Exception as e:
        print(f"Error saving report: {str(e)}")
        return False

def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(description="Bcachefs Doctor - Comprehensive filesystem diagnostics")
    parser.add_argument("-u", "--uuid", help="Specific bcachefs UUID to analyze")
    parser.add_argument("-m", "--mountpoint", help="Analyze filesystem by mountpoint")
    parser.add_argument("-a", "--all", action="store_true", help="Analyze all bcachefs instances")
    parser.add_argument("-j", "--json", action="store_true", help="Output in JSON format")
    parser.add_argument("-o", "--output", help="Save report to file")
    parser.add_argument("--no-color", action="store_true", help="Disable colored output")
    args = parser.parse_args()
    
    # Disable colors if requested
    if args.no_color:
        for attr in dir(Colors):
            if not attr.startswith("__"):
                setattr(Colors, attr, "")
    
    # Check if bcachefs exists in /sys
    if not os.path.exists("/sys/fs/bcachefs"):
        print(f"{Colors.RED}Error: Bcachefs filesystem not detected in sysfs!{Colors.ENDC}")
        print(f"{Colors.YELLOW}Make sure bcachefs module is loaded.{Colors.ENDC}")
        sys.exit(1)
    
    # Determine which filesystems to analyze
    if args.uuid:
        # Analyze a specific bcachefs instance by UUID
        fs_info = process_fs_info(args.uuid)
        if "error" in fs_info:
            print(f"{Colors.RED}Error: {fs_info['error']}{Colors.ENDC}")
            sys.exit(1)
        
        if args.json:
            report = format_report_json(fs_info)
        else:
            report = format_report_text(fs_info)
        
        if args.output:
            if save_report(report, args.output):
                print(f"Report saved to {args.output}")
            else:
                print(f"{Colors.RED}Failed to save report{Colors.ENDC}")
        else:
            print(report)
    
    elif args.mountpoint:
        # Find the UUID for this mountpoint
        mounted_fs = get_mounted_filesystems()
        uuid = None
        
        for fs in mounted_fs:
            if fs["mountpoint"] == args.mountpoint:
                # Get UUID from device path
                for instance in find_bcachefs_instances():
                    # Run a simple check to see if this is the right instance
                    status = run_bcachefs_status(args.mountpoint)
                    if status and "parsed" in status and "UUID" in status["parsed"]:
                        if status["parsed"]["UUID"] == instance:
                            uuid = instance
                            break
        
        if not uuid:
            print(f"{Colors.RED}Error: Could not find bcachefs instance for mountpoint {args.mountpoint}{Colors.ENDC}")
            sys.exit(1)
        
        fs_info = process_fs_info(uuid)
        if "error" in fs_info:
            print(f"{Colors.RED}Error: {fs_info['error']}{Colors.ENDC}")
            sys.exit(1)
        
        if args.json:
            report = format_report_json(fs_info)
        else:
            report = format_report_text(fs_info)
        
        if args.output:
            if save_report(report, args.output):
                print(f"Report saved to {args.output}")
            else:
                print(f"{Colors.RED}Failed to save report{Colors.ENDC}")
        else:
            print(report)
    
    elif args.all:
        # Analyze all bcachefs instances
        instances = find_bcachefs_instances()
        if not instances:
            print(f"{Colors.RED}No bcachefs instances found!{Colors.ENDC}")
            sys.exit(1)
        
        all_reports = []
        for instance in instances:
            fs_info = process_fs_info(instance)
            all_reports.append(fs_info)
            
            if not args.json and not args.output:
                print(format_report_text(fs_info))
                print("\n" + "=" * 80 + "\n")
        
        if args.json:
            # Combine all reports
            combined_report = {
                "system": get_system_info(),
                "kernel": get_kernel_info(),
                "filesystems": all_reports,
                "generated_at": datetime.now().isoformat()
            }
            report = json.dumps(combined_report, indent=2)
            
            if args.output:
                if save_report(report, args.output):
                    print(f"Combined report saved to {args.output}")
                else:
                    print(f"{Colors.RED}Failed to save report{Colors.ENDC}")
            else:
                print(report)
    
    else:
        # Check if there's only one instance
        instances = find_bcachefs_instances()
        if not instances:
            print(f"{Colors.RED}No bcachefs instances found!{Colors.ENDC}")
            sys.exit(1)
        elif len(instances) == 1:
            # If there's only one instance, analyze it
            fs_info = process_fs_info(instances[0])
            if "error" in fs_info:
                print(f"{Colors.RED}Error: {fs_info['error']}{Colors.ENDC}")
                sys.exit(1)
            
            if args.json:
                report = format_report_json(fs_info)
            else:
                report = format_report_text(fs_info)
            
            if args.output:
                if save_report(report, args.output):
                    print(f"Report saved to {args.output}")
                else:
                    print(f"{Colors.RED}Failed to save report{Colors.ENDC}")
            else:
                print(report)
        else:
            # Multiple instances but no specific one selected
            print(f"{Colors.YELLOW}Multiple bcachefs instances found. Please specify one with --uuid or use --all:{Colors.ENDC}")
            for instance in instances:
                print(f"  {instance}")
            sys.exit(1)

if __name__ == "__main__":
    main()
