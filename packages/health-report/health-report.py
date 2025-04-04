#!/usr/bin/env python3
"""
Server Health Reporter

A Python implementation of the server health monitoring service.
This script collects system health metrics and sends reports via Telegram.
"""

import os
import sys
import time
import json
import logging
import argparse
import platform
import subprocess
import tempfile
import re
from datetime import datetime
from pathlib import Path
import psutil
import requests
import shutil
from hurry.filesize import size

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("health-reporter")

class ConfigurationError(Exception):
    """Exception raised for configuration errors."""
    pass

class ReportSection:
    """Base class for report sections - enables easy extension with new metrics"""
    def __init__(self, reporter):
        self.reporter = reporter
        self.config = reporter.config
    
    def collect_summary(self):
        """Collect data for summary report - should be implemented by subclasses"""
        return []

    def collect_detailed(self):
        """Collect data for detailed report - should be implemented by subclasses"""
        return []

class UptimeSection(ReportSection):
    """System uptime information"""
    def collect_summary(self):
        boot_time = psutil.boot_time()
        uptime_seconds = time.time() - boot_time
        uptime_days = int(uptime_seconds // 86400)
        uptime_hours = int((uptime_seconds % 86400) // 3600)
        uptime_minutes = int((uptime_seconds % 3600) // 60)
        
        if uptime_days > 0:
            uptime_info = f"up {uptime_days} days, {uptime_hours}:{uptime_minutes:02d}"
        else:
            uptime_info = f"up {uptime_hours}:{uptime_minutes:02d}"
            
        return [f"⏱️ *Uptime:* {uptime_info}"]
    
    def collect_detailed(self):
        boot_time = datetime.fromtimestamp(psutil.boot_time()).strftime("%Y-%m-%d %H:%M:%S")
        return ["*UPTIME:*", f"System booted at: {boot_time}", ""]

class CPUSection(ReportSection):
    """CPU usage and information"""
    def collect_summary(self):
        # Load average
        if hasattr(os, "getloadavg"):  # Unix-like systems
            load1, load5, load15 = os.getloadavg()
            load_str = f"{load1:.2f}, {load5:.2f}, {load15:.2f}"
        else:  # Windows or other systems
            cpu_percent = psutil.cpu_percent(interval=1)
            load_str = f"{cpu_percent:.2f}%"
            load1 = cpu_percent / 100.0
        
        cpu_count = psutil.cpu_count()
        
        # Determine status icon
        if load1 > cpu_count * 0.8:
            load_icon = "🔴"
        elif load1 > cpu_count * 0.5:
            load_icon = "🟡"
        else:
            load_icon = "🟢"
        
        return [f"{load_icon} *Load:* {load_str} ({cpu_count} CPU cores)"]
    
    def collect_detailed(self):
        lines = ["*CPU INFORMATION:*"]
        
        # CPU model and architecture
        cpu_info = platform.processor() or "Unknown"
        cpu_arch = platform.machine() or "Unknown"
        lines.append(f"Model: {cpu_info}")
        lines.append(f"Architecture: {cpu_arch}")
        
        # CPU cores and threads
        physical_cores = psutil.cpu_count(logical=False) or 0
        logical_cores = psutil.cpu_count(logical=True) or 0
        lines.append(f"Physical cores: {physical_cores}")
        lines.append(f"Logical cores: {logical_cores}")
        
        # CPU frequency
        if hasattr(psutil, "cpu_freq"):
            freq = psutil.cpu_freq()
            if freq:
                lines.append(f"Frequency: Current={freq.current:.2f} MHz, Max={freq.max:.2f} MHz")
        
        # CPU temperature - platform specific, try different methods
        temp_info = self._get_cpu_temperature()
        if temp_info:
            lines.append(f"Temperature: {temp_info}")
        
        # CPU load
        if hasattr(os, "getloadavg"):
            load1, load5, load15 = os.getloadavg()
            lines.append(f"Load average: {load1:.2f}, {load5:.2f}, {load15:.2f}")
        
        lines.append("")
        return lines
    
    def _get_cpu_temperature(self):
        """Try multiple methods to get CPU temperature"""
        # Try psutil first
        if hasattr(psutil, "sensors_temperatures"):
            temps = psutil.sensors_temperatures()
            if temps:
                for name, entries in temps.items():
                    for entry in entries:
                        if entry.label and ('cpu' in entry.label.lower() or 'core' in entry.label.lower()):
                            return f"{entry.current:.1f}°C"
                # If no CPU-specific temp found, use the first one
                for name, entries in temps.items():
                    if entries:
                        return f"{entries[0].current:.1f}°C"
        
        # Try reading from system file
        try:
            if os.path.exists("/sys/class/thermal/thermal_zone0/temp"):
                with open("/sys/class/thermal/thermal_zone0/temp") as f:
                    temp = int(f.read().strip()) / 1000
                    return f"{temp:.1f}°C"
        except:
            pass
        
        # Try using 'sensors' command
        try:
            output = subprocess.check_output(["sensors"], text=True)
            for line in output.split("\n"):
                if "Core" in line or "CPU" in line:
                    match = re.search(r"\+(\d+\.\d+)°C", line)
                    if match:
                        return f"{match.group(1)}°C"
        except:
            pass
            
        return None

class MemorySection(ReportSection):
    """Memory usage information"""
    def collect_summary(self):
        memory = psutil.virtual_memory()
        mem_total = size(memory.total)
        mem_used = size(memory.used)
        mem_pct = memory.percent
        
        # Determine status icon
        if mem_pct >= 90:
            mem_icon = "🔴"
        elif mem_pct >= 75:
            mem_icon = "🟡"
        else:
            mem_icon = "🟢"
            
        return [f"{mem_icon} *Memory:* {mem_used}/{mem_total} ({mem_pct:.1f}%)"]
    
    def collect_detailed(self):
        lines = ["*MEMORY USAGE:*"]
        
        # Virtual memory
        vm = psutil.virtual_memory()
        lines.append(f"Total: {size(vm.total)}")
        lines.append(f"Used: {size(vm.used)} ({vm.percent:.1f}%)")
        lines.append(f"Available: {size(vm.available)}")
        
        # Swap memory
        swap = psutil.swap_memory()
        if swap.total > 0:
            lines.append("")
            lines.append("*SWAP USAGE:*")
            lines.append(f"Total: {size(swap.total)}")
            lines.append(f"Used: {size(swap.used)} ({swap.percent:.1f}%)")
            lines.append(f"Free: {size(swap.free)}")
        
        lines.append("")
        return lines
    

class DiskSection(ReportSection):
    """Disk usage and health information"""
    def collect_summary(self):
        lines = ["💾 *Disk Usage:*"]
        
        # Get disk partitions, excluding special filesystems
        for part in psutil.disk_partitions(all=False):
            mount_point = part.mountpoint
            
            # Skip excluded mount points
            if self._should_exclude_mount(mount_point):
                continue
                
            try:
                usage = psutil.disk_usage(mount_point)
                percent = usage.percent
                
                # Determine status emoji
                status_emoji = self._get_disk_status_emoji(percent)
                
                total_size = size(usage.total)
                used_size = size(usage.used)
                                    
                lines.append(f"{status_emoji} {mount_point}: {used_size}/{total_size} ({percent:.1f}%)")
            except (PermissionError, FileNotFoundError):
                continue

        # Add S.M.A.R.T information if available
        # TODO: add summary flag to smart data
        smart_info = self._get_smart_info()
        if smart_info:
            lines.append("")
            lines.extend(smart_info)
            
        lines.append("")
                
        return lines
    
    def collect_detailed(self):
        lines = ["*DISK USAGE:*"]
        
        # Header
        lines.append(f"{'Filesystem':<20} {'Size':<8} {'Used':<8} {'Avail':<8} {'Use%':<6} {'Mounted on'}")
        
        # Get disk partitions
        for part in psutil.disk_partitions(all=False):
            mount_point = part.mountpoint
            
            # Skip excluded mount points
            if self._should_exclude_mount(mount_point):
                continue
                
            try:
                usage = psutil.disk_usage(mount_point)
                filesystem = part.device
                
                # Format sizes
                total_size = size(usage.total)
                used = size(usage.used)
                avail = size(usage.free)
                
                # Format output
                lines.append(
                    f"{filesystem[:19]:<20} {total_size:<8} {used:<8} {avail:<8} "
                    f"{usage.percent:<6.1f} {mount_point}"
                )
            except (PermissionError, FileNotFoundError):
                continue
        
        # Add S.M.A.R.T information if available
        smart_info = self._get_smart_info()
        if smart_info:
            lines.append("")
            lines.extend(smart_info)
            
        lines.append("")
        return lines
    
    def _should_exclude_mount(self, mount_point):
        """Check if a mount point should be excluded based on patterns"""
        exclude_patterns = self.config.get("exclude_mount_points", [])
        
        for pattern in exclude_patterns:
            if pattern in mount_point:
                return True
                
        # Also exclude common temporary filesystems
        if any(fs in mount_point for fs in ["/dev", "/sys", "/proc", "/run", "/boot/efi"]):
            return True
            
        return False
    
    def _get_disk_status_emoji(self, usage_percent):
        """Get disk status emoji based on usage percentage"""
        critical = self.config.get("critical_disk_usage", 90)
        warning = self.config.get("warning_disk_usage", 75)
        
        if usage_percent >= critical:
            return "🔴"
        elif usage_percent >= warning:
            return "🟡"
        else:
            return "🟢"
    
    def _get_smart_info(self):
        """Get S.M.A.R.T. information for physical drives using JSON output"""
        lines = ["*DRIVE HEALTH (S.M.A.R.T):*"]
    
        # Check for smartctl command
        smartctl_path = shutil.which("smartctl")
        if not smartctl_path:
            lines.append("S.M.A.R.T. not available - smartctl command not found")
            return lines
        
        # For Linux
        if os.path.exists("/dev"):
            # Get physical drives
            drives = []
            try:
                output = subprocess.check_output(
                    ["lsblk", "-d", "-o", "NAME,TYPE,SERIAL,SIZE", "--json"],
                    text=True,
                    stderr=subprocess.DEVNULL
                )
                # Parse JSON output
                devices_data = json.loads(output)

                # Filter to only include disks
                block_devices = [
                    device for device in devices_data.get("blockdevices", [])
                    if device.get("type") == "disk"
                ]

                # Filter out excluded drives
                exclude_patterns = self.config.get("exclude_drives", [])
                for device in block_devices:
                    dev_name = device.get("name", "")
                    if not any(pattern in dev_name for pattern in exclude_patterns):
                        # Add to drives list with additional info
                        drives.append({
                            "path": f"/dev/{dev_name}",
                            "serial": device.get("serial", "N/A"),
                            "size": device.get("size", "Unknown")
                        })
            except Exception as e:
                logger.error(f"Error detecting drives: {e}")

        # No drives detected
        if not drives:
            lines.append("No drives detected for monitoring.")
            return lines
        
        # Check each drive
        for drive in drives:
            drive_path = drive["path"]
            # Display with serial number if available
            display_name = f"{drive_path} ({drive['serial']})" if drive['serial'] and drive['serial'] != "" else drive_path
            lines.append(f"Drive {display_name}:")
    
            # Check if this is a virtual drive (vd*) or physical drive
            is_virtual_drive = re.match(r'/dev/vd[a-z]', drive_path) is not None
        
            if is_virtual_drive:
                # For virtual drives, don't try to check SMART status
                lines.append(f"  ℹ️ Virtual drive - SMART not applicable")
                lines.append(f"  Size: {drive['size']}")
                lines.append("")
                continue
            
            # Check SMART health status using JSON output
            try:
                # First check if SMART is available for this drive
                basic_check = subprocess.run(
                    ["smartctl", "-i", drive_path, "--json"],
                    capture_output=True,
                    text=True
                )
            
                # Try to parse the output as JSON
                try:
                    basic_data = json.loads(basic_check.stdout)
                
                    # Check if SMART is available and enabled
                    smart_available = False
                    smart_enabled = False
                
                    # For ATA drives
                    if "smart_support" in basic_data:
                        smart_support = basic_data.get("smart_support", {})
                        smart_available = smart_support.get("available", False)
                        smart_enabled = smart_support.get("enabled", False)
                
                    # For NVMe drives, SMART (or NVMe SMART equivalent) is always available
                    elif "device" in basic_data and basic_data.get("device", {}).get("protocol") == "NVMe":
                        smart_available = True
                        smart_enabled = True
                
                    # If SMART is not available or enabled, report this
                    if not smart_available:
                        lines.append(f"  ⚠️ SMART not available for this drive")
                        lines.append(f"  Size: {drive['size']}")
                        lines.append("")
                        continue
                    elif not smart_enabled:
                        lines.append(f"  ⚠️ SMART available but not enabled for this drive")
                        lines.append(f"  Size: {drive['size']}")
                        lines.append("")
                        continue
                    
                except json.JSONDecodeError:
                    # If we can't parse the output, check if the return code indicates an issue
                    # Non-zero return code usually means the command failed
                    if basic_check.returncode != 0 and "Device does not support SMART" in basic_check.stderr:
                        lines.append(f"  ⚠️ Device does not support SMART")
                        lines.append(f"  Size: {drive['size']}")
                        lines.append("")
                        continue
            
                # Use smartctl with JSON output for health status
                health_output = subprocess.run(
                    ["smartctl", "-H", drive_path, "--json"],
                    capture_output=True,
                    text=True
                )
            
                try:
                    health_data = json.loads(health_output.stdout)
                
                    # Get exit status to check for warnings
                    exit_status = health_data.get("smartctl", {}).get("exit_status", 0)
                    has_warnings = (exit_status & 32) == 32  # Check if bit 5 is set (historical warnings)
                
                    # Check for unsupported device
                    if (exit_status & 4) == 4:  # Check if bit 2 is set (unsupported device)
                        lines.append(f"  ⚠️ SMART not supported for this device")
                        lines.append(f"  Size: {drive['size']}")
                        lines.append("")
                        continue
                
                    # Get overall health status
                    smart_status = health_data.get("smart_status", {})
                    health_passed = smart_status.get("passed", False)
                
                    # Determine status emoji based on health and warnings
                    if health_passed:
                        if has_warnings:
                            health_emoji = "🟡"  # Passed but with warnings
                            health_status = "PASSED (with warnings)"
                        else:
                            health_emoji = "🟢"  # Fully passed
                            health_status = "PASSED"
                    else:
                        health_emoji = "🔴"  # Failed
                        health_status = "FAILED"
                
                    lines.append(f"  {health_emoji} Health status: {health_status}")
                
                    # Add size info
                    lines.append(f"  Size: {drive['size']}")
                
                    # Get drive type for specific attribute handling
                    drive_type = health_data.get("device", {}).get("type", "")
                
                    # Get detailed SMART attributes using JSON
                    attributes_output = subprocess.run(
                        ["smartctl", "-A", drive_path, "--json"],
                        capture_output=True,
                        text=True
                    )
                
                    try:
                        attr_data = json.loads(attributes_output.stdout)
                    
                        # Add temperature information if available in the top level
                        if "temperature" in attr_data and "current" in attr_data["temperature"]:
                            temp = attr_data["temperature"]["current"]
                            lines.append(f"  Temperature: {temp}°C")
                    
                        # Handle NVMe drives
                        if drive_type == "nvme" or "nvme_smart_health_information_log" in attr_data:
                            nvme_health = attr_data.get("nvme_smart_health_information_log", {})
                        
                            # Add NVMe specific health metrics
                            if "percentage_used" in nvme_health:
                                lines.append(f"  Percentage used: {nvme_health['percentage_used']}%")
                        
                            if "available_spare" in nvme_health:
                                lines.append(f"  Available spare: {nvme_health['available_spare']}%")
                        
                            # Check for critical warnings
                            if nvme_health.get("critical_warning", 0) > 0:
                                lines.append("  ⚠️ Drive has critical warnings")
                        
                            # Check for media errors
                            if "media_errors" in nvme_health and nvme_health["media_errors"] > 0:
                                lines.append(f"  Media errors: {nvme_health['media_errors']}")
                            
                            # Add power-on time if available
                            if "power_on_time" in attr_data and "hours" in attr_data["power_on_time"]:
                                hours = attr_data["power_on_time"]["hours"]
                                lines.append(f"  Power on time: {hours} hours")
                    
                        # Handle SATA/SAS drives
                        elif (drive_type in ["sat", "scsi", "ata"] or 
                              "ata_smart_attributes" in attr_data):
                        
                            # Get attributes table if available
                            ata_attrs = attr_data.get("ata_smart_attributes", {}).get("table", [])
                        
                            # Track important attributes and their display names
                            important_attrs = {
                                "Reallocated_Sector_Ct": "Reallocated Sectors",
                                "Current_Pending_Sector": "Current Pending Sectors",
                                "Offline_Uncorrectable": "Offline Uncorrectable",
                                "Airflow_Temperature_Cel": "Airflow Temperature",
                                "Temperature_Celsius": "Temperature",
                                "Power_On_Hours": "Power On Hours",
                                "Power_Cycle_Count": "Power Cycles",
                                "UDMA_CRC_Error_Count": "UDMA CRC Errors"
                            }
                        
                            # Process each attribute
                            for attr in ata_attrs:
                                attr_name = attr.get("name", "")
                                attr_value = attr.get("raw", {}).get("value", 0)
                            
                                # Check for when_failed status
                                when_failed = attr.get("when_failed", "")
                                has_failed = when_failed in ["now", "past"]
                            
                                # Special handling for temperature
                                if "Temperature" in attr_name or "Airflow_Temperature" in attr_name:
                                    # Temperature is often stored in the raw value
                                    # Some drives use weird formats like "33 (Min/Max 33/43)"
                                    temp_str = str(attr.get("raw", {}).get("string", ""))
                                    try:
                                        # Try to extract the first number from the string
                                        temp_match = re.search(r'\d+', temp_str)
                                        if temp_match:
                                            temp = int(temp_match.group())
                                            lines.append(f"  Temperature: {temp}°C")
                                    except:
                                        # Fallback to using the raw value directly
                                        if attr_value:
                                            lines.append(f"  Temperature: {attr_value}°C")
                                # Handle other important attributes
                                elif attr_name in important_attrs and (attr_value > 0 or has_failed):
                                    display_name = important_attrs[attr_name]
                                
                                    # Add warning emoji if the attribute has failed
                                    prefix = "  ⚠️ " if has_failed else "  "
                                    lines.append(f"{prefix}{display_name}: {attr_value}")
                
                    except (json.JSONDecodeError, KeyError) as e:
                        lines.append(f"  Error parsing SMART attributes: {str(e)}")
            
                except (json.JSONDecodeError, KeyError) as e:
                    lines.append(f"  Error parsing SMART health status: {str(e)}")
                
            except Exception as e:
                lines.append(f"  Error checking drive: {str(e)}")
            
            lines.append("")
        
        return lines


class NetworkSection(ReportSection):
    """Network interface and traffic information"""
    def collect_summary(self):
        if not self.config.get("enable_network_monitoring", True):
            return []
            
        lines = ["🌐 *Network:*"]
        
        # Get primary interface (excluding lo, virtual interfaces)
        primary_if = self._get_primary_interface()
        if not primary_if:
            lines.append("No primary network interface found")
            return lines
            
        # Get network stats for the primary interface
        stats = psutil.net_io_counters(pernic=True).get(primary_if)
        if stats:
            rx_bytes = stats.bytes_recv
            tx_bytes = stats.bytes_sent
            rx_human = size(rx_bytes)
            tx_human = size(tx_bytes)
            lines.append(f"{primary_if}: ↓{rx_human} ↑{tx_human}")
        
        return lines
    
    def collect_detailed(self):
        if not self.config.get("enable_network_monitoring", True):
            return []
            
        lines = ["*NETWORK STATS:*"]
        lines.append("Interfaces:")
        
        # Get active network interfaces
        for iface, addrs in psutil.net_if_addrs().items():
            # Skip loopback and virtual interfaces
            if iface == "lo" or "virtual" in iface.lower() or "docker" in iface.lower():
                continue
                
            # Get addresses
            ip_addresses = []
            for addr in addrs:
                if addr.family == socket.AF_INET:  # IPv4
                    ip_addresses.append(f"IPv4: {addr.address}")
                elif addr.family == socket.AF_INET6:  # IPv6
                    ip_addresses.append(f"IPv6: {addr.address}")
            
            if ip_addresses:
                lines.append(f"  {iface}: {', '.join(ip_addresses)}")
        
        lines.append("")
        lines.append("Traffic Statistics:")
        
        # Get statistics for each interface
        stats = psutil.net_io_counters(pernic=True)
        for iface, iface_stats in stats.items():
            # Skip loopback and virtual interfaces
            if iface == "lo" or "virtual" in iface.lower() or "docker" in iface.lower():
                continue
                
            rx_bytes = size(iface_stats.bytes_recv)
            tx_bytes = size(iface_stats.bytes_sent)
            rx_packets = iface_stats.packets_recv
            tx_packets = iface_stats.packets_sent
            
            lines.append(f"  {iface}:")
            lines.append(f"    Received: {rx_bytes} ({rx_packets} packets)")
            lines.append(f"    Sent: {tx_bytes} ({tx_packets} packets)")
            
        lines.append("")
        return lines
    
    def _get_primary_interface(self):
        """Get the primary network interface"""
        # Try to find the interface with a default route
        try:
            # For Linux
            if os.path.exists("/proc/net/route"):
                with open("/proc/net/route") as f:
                    for line in f:
                        parts = line.strip().split()
                        if len(parts) >= 11 and parts[1] == "00000000" and parts[7] == "00000000":
                            return parts[0]
        except:
            pass
            
        # Fallback: use the first non-loopback interface with an IPv4 address
        for iface, addrs in psutil.net_if_addrs().items():
            if iface != "lo" and "virtual" not in iface.lower() and "docker" not in iface.lower():
                for addr in addrs:
                    if getattr(addr, "family", None) == socket.AF_INET:  # IPv4
                        return iface
        
        return None
    

class ProcessesSection(ReportSection):
    """Information about top processes"""
    def collect_summary(self):
        # Get top process by CPU
        top_process = self._get_top_process_by_cpu()
        if top_process:
            proc_name = top_process.get('name', 'Unknown')
            cpu_percent = top_process.get('cpu_percent', 0)
            return [f"🔄 *Top CPU:* {proc_name} ({cpu_percent:.1f}%)"]
        return []
    
    def collect_detailed(self):
        lines = ["*TOP PROCESSES BY CPU:*"]
        lines.append(f"{'PID':<8} {'PPID':<8} {'CPU%':<8} {'MEM%':<8} {'Command'}")
        
        # Get top CPU processes
        top_cpu_processes = self._get_top_processes_by_cpu(5)
        for proc in top_cpu_processes:
            pid = proc.get('pid', 'N/A')
            ppid = proc.get('ppid', 'N/A')
            cpu_percent = proc.get('cpu_percent', 0)
            memory_percent = proc.get('memory_percent', 0)
            name = proc.get('name', 'Unknown')
            cmd = proc.get('cmdline', 'Unknown')
            
            # Truncate command if too long
            if len(cmd) > 50:
                cmd = cmd[:47] + "..."
                
            lines.append(f"{pid:<8} {ppid:<8} {cpu_percent:<8.1f} {memory_percent:<8.1f} {cmd}")
        
        lines.append("")
        lines.append("*TOP PROCESSES BY MEMORY:*")
        lines.append(f"{'PID':<8} {'PPID':<8} {'CPU%':<8} {'MEM%':<8} {'Command'}")
        
        # Get top memory processes
        top_mem_processes = self._get_top_processes_by_memory(5)
        for proc in top_mem_processes:
            pid = proc.get('pid', 'N/A')
            ppid = proc.get('ppid', 'N/A')
            cpu_percent = proc.get('cpu_percent', 0)
            memory_percent = proc.get('memory_percent', 0)
            name = proc.get('name', 'Unknown')
            cmd = proc.get('cmdline', 'Unknown')
            
            # Truncate command if too long
            if len(cmd) > 50:
                cmd = cmd[:47] + "..."
                
            lines.append(f"{pid:<8} {ppid:<8} {cpu_percent:<8.1f} {memory_percent:<8.1f} {cmd}")
        
        lines.append("")
        return lines
    
    def _get_top_process_by_cpu(self):
        """Get the top process by CPU usage"""
        processes = self._get_processes_info()
        if processes:
            # Sort by CPU usage (descending)
            sorted_processes = sorted(processes, key=lambda x: x.get('cpu_percent', 0), reverse=True)
            return sorted_processes[0] if sorted_processes else None
        return None
    
    def _get_top_processes_by_cpu(self, limit=5):
        """Get the top N processes by CPU usage"""
        processes = self._get_processes_info()
        if processes:
            # Sort by CPU usage (descending)
            sorted_processes = sorted(processes, key=lambda x: x.get('cpu_percent', 0), reverse=True)
            return sorted_processes[:limit]
        return []
    
    def _get_top_processes_by_memory(self, limit=5):
        """Get the top N processes by memory usage"""
        processes = self._get_processes_info()
        if processes:
            # Sort by memory usage (descending)
            sorted_processes = sorted(processes, key=lambda x: x.get('memory_percent', 0), reverse=True)
            return sorted_processes[:limit]
        return []
    
    def _get_processes_info(self):
        """Get information about all running processes"""
        processes = []
        
        for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent', 'ppid', 'cmdline']):
            try:
                pinfo = proc.info
                
                # Get command line
                try:
                    cmdline = " ".join(proc.cmdline())
                except:
                    cmdline = pinfo['name']
                
                if not cmdline:
                    cmdline = pinfo['name']
                
                processes.append({
                    'pid': pinfo['pid'],
                    'name': pinfo['name'],
                    'cpu_percent': pinfo['cpu_percent'],
                    'memory_percent': pinfo['memory_percent'],
                    'ppid': pinfo['ppid'],
                    'cmdline': cmdline
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                pass
                
        # Update CPU usage for all processes
        psutil.cpu_percent(interval=0.1)  # Short delay to get more accurate readings
        for proc in processes:
            try:
                proc['cpu_percent'] = psutil.Process(proc['pid']).cpu_percent(interval=0)
            except:
                pass
                
        return processes

class HealthReporter:
    def __init__(self, config_file=None, config_dict=None):
        """
        Initialize the Health Reporter with either a config file or dictionary.
        
        Args:
            config_file (str, optional): Path to the configuration file.
            config_dict (dict, optional): Configuration dictionary.
        """
        self.config = {
            # Default configuration values
            "send_to_telegram": False,
            "telegram_token_path": "/run/secrets/telegram-token",
            "telegram_chat_id_path": "/run/secrets/telegram-chatid",
            "report_time": "06:00",
            "enable_cpu_monitoring": True,
            "enable_memory_monitoring": True,
            "enable_network_monitoring": True,
            "exclude_drives": [],
            "exclude_mount_points": [
                "/run", 
                "/var/lib/docker", 
                "/var/lib/containers",
                "k3s",
                "kube",
                "containerd",
                "docker",
                "sandbox"
            ],
            "critical_disk_usage": 90,
            "warning_disk_usage": 75,
            "detailed_report": False
        }
        
        # Load configuration from file or dictionary
        if config_file:
            self._load_config_from_file(config_file)
        elif config_dict:
            self.config.update(config_dict)
            
        # Initialize report sections - easy to add new sections here
        self.report_sections = [
            UptimeSection(self),
            CPUSection(self),
            MemorySection(self),
            DiskSection(self),
            NetworkSection(self),
            ProcessesSection(self)
        ]
            
        # Initialize variables
        self.telegram_token = None
        self.telegram_chat_id = None
        self.hostname = platform.node()
        self.current_date = datetime.now().strftime("%Y-%m-%d %H:%M")

    def _load_config_from_file(self, config_file):
        """Load configuration from a file."""
        try:
            with open(config_file, 'r') as f:
                config_data = json.load(f)
                self.config.update(config_data)
                logger.info(f"Configuration loaded from {config_file}")
        except (json.JSONDecodeError, FileNotFoundError) as e:
            logger.error(f"Error loading configuration: {str(e)}")
            raise ConfigurationError(f"Failed to load configuration: {str(e)}")

    def _load_telegram_credentials(self):
        """Load Telegram credentials from specified paths."""
        # Read the Telegram token
        token_path = Path(self.config["telegram_token_path"])
        chat_id_path = Path(self.config["telegram_chat_id_path"])
        
        if not token_path.exists():
            raise ConfigurationError(f"Telegram token file not found at {token_path}")
            
        if not chat_id_path.exists():
            raise ConfigurationError(f"Telegram chat ID file not found at {chat_id_path}")
            
        try:
            self.telegram_token = token_path.read_text().strip()
            self.telegram_chat_id = chat_id_path.read_text().strip()
        except Exception as e:
            raise ConfigurationError(f"Failed to read Telegram credentials: {str(e)}")

    def generate_summary_report(self):
        """Generate a summary health report."""
        lines = ["*SERVER HEALTH SUMMARY*"]
        lines.append(f"📊 *{self.hostname}* - {self.current_date}")
        lines.append("")
        
        # Collect data from each section
        for section in self.report_sections:
            section_lines = section.collect_summary()
            if section_lines:
                lines.extend(section_lines)
                lines.append("")
        
        return "\n".join(lines)

    def generate_detailed_report(self):
        """Generate a detailed health report."""
        if not self.config.get("detailed_report", False):
            return None
            
        lines = ["*SERVER HEALTH REPORT*"]
        lines.append(f"📊 *{self.hostname}* - {self.current_date}")
        lines.append("")
        
        # Collect data from each section
        for section in self.report_sections:
            section_lines = section.collect_detailed()
            if section_lines:
                lines.extend(section_lines)
                
        return "\n".join(lines)
        
    def send_telegram_message(self, message):
        """Send a message to Telegram."""
        # Make sure the message doesn't exceed Telegram's limit
        if len(message) > 4000:
            message = message[:3950] + "...\n(Message truncated due to length limits)"
            
        try:
            response = requests.post(
                f"https://api.telegram.org/bot{self.telegram_token}/sendMessage",
                data={
                    "chat_id": self.telegram_chat_id,
                    "text": message,
                    "parse_mode": "Markdown"
                }
            )
            response.raise_for_status()
            return True
        except Exception as e:
            logger.error(f"Failed to send Telegram message: {str(e)}")
            return False
            
    def send_detailed_report_in_sections(self, detailed_report):
        """Send a detailed report to Telegram in manageable sections."""
        # Split the report into logical sections
        sections = []
        current_section = []
        current_section_size = 0
        max_section_size = 3500  # Telegram limit is 4096, but leave some margin
        
        for line in detailed_report.split("\n"):
            # Start a new section for main headers or if current section is getting too large
            if line.startswith("*") and not line.startswith("**") and current_section_size > 0:
                sections.append("\n".join(current_section))
                current_section = []
                current_section_size = 0
            
            current_section.append(line)
            current_section_size += len(line) + 1  # +1 for newline
            
            # If section is getting too large, break it
            if current_section_size > max_section_size:
                sections.append("\n".join(current_section))
                current_section = []
                current_section_size = 0
                
        # Add the last section if it's not empty
        if current_section:
            sections.append("\n".join(current_section))
            
        # Send each section
        success = True
        for i, section in enumerate(sections):
            if not self.send_telegram_message(section):
                success = False
            # Add a short delay between messages to avoid rate limiting
            if i < len(sections) - 1:
                time.sleep(1)
                
        return success
        
    def run(self):
        """Execute the health report process."""
        try:
            
            # Generate the summary report
            summary_report = self.generate_summary_report()
            logger.info("Summary report generated")
            logger.info(summary_report)
            
            # Load Telegram credentials
            if self.config.get("send_to_telegram"):
                self._load_telegram_credentials()
                # Send the summary report
                if not self.send_telegram_message(summary_report):
                    logger.error("Failed to send summary report")
                    return False
                
            # Generate and send the detailed report if enabled
            if self.config.get("detailed_report", False):
                detailed_report = self.generate_detailed_report()
                logger.info(detailed_report)
                if detailed_report:
                    logger.info("Detailed report generated")
                    if self.config.get("send_to_telegram"):
                        if not self.send_detailed_report_in_sections(detailed_report):
                            logger.error("Failed to send detailed report")
                            return False
                        
            return True
            
        except Exception as e:
            logger.error(f"Error during health report execution: {str(e)}")
            return False

def main():
    """Main entry point for the script."""
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Server Health Reporter")
    parser.add_argument("--config", help="Path to the configuration file")
    parser.add_argument("--send-to-telegram", action="store_true", help="Send report to Telegram")
    parser.add_argument("--telegram-token-path", help="Path to the Telegram token file")
    parser.add_argument("--telegram-chat-id-path", help="Path to the Telegram chat ID file")
    parser.add_argument("--detailed", action="store_true", help="Generate detailed report")
    args = parser.parse_args()
    

    # Validate that Telegram-related arguments are provided if --send-to-telegram is active
    if args.send_to_telegram:
        if not args.telegram_token_path or not args.telegram_chat_id_path:
            parser.error("--telegram-token-path and --telegram-chat-id-path are required when --send-to-telegram is active")
    # Create configuration dictionary from arguments
    config_dict = {}
    if args.send_to_telegram:
        config_dict["send_to_telegram"] = args.send_to_telegram
    if args.telegram_token_path:
        config_dict["telegram_token_path"] = args.telegram_token_path
    if args.telegram_chat_id_path:
        config_dict["telegram_chat_id_path"] = args.telegram_chat_id_path
    if args.detailed:
        config_dict["detailed_report"] = True
        
    try:
        # Create and run the reporter
        if args.config:
            reporter = HealthReporter(config_file=args.config)
        else:
            reporter = HealthReporter(config_dict=config_dict)
            
        if reporter.run():
            logger.info("Health report completed successfully")
            sys.exit(0)
        else:
            logger.error("Health report failed")
            sys.exit(1)
            
    except ConfigurationError as e:
        logger.error(str(e))
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    # Add import that's needed here to avoid circular imports
    import socket
    main()
