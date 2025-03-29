#!/usr/bin/env python3
"""
bcachefs I/O Metrics

A script to gather and report I/O metrics from bcachefs filesystems.
It parses the io_done files in /sys/fs/bcachefs and presents
metrics grouped by device type (ssd, nvme, hdd).
"""

import os
import glob
import argparse
import sys
from pathlib import Path

def format_bytes(num_bytes):
    """
    Convert a number of bytes into a human-readable string using binary units.
    """
    num = float(num_bytes)
    for unit in ['B', 'KiB', 'MiB', 'GiB', 'TiB']:
        if num < 1024:
            return f"{num:.2f} {unit}"
        num /= 1024
    return f"{num:.2f} PiB"

def parse_io_done(file_path):
    """
    Parse an io_done file.
    The file is expected to have two sections ("read:" and "write:")
    followed by lines with "key : value" pairs.

    Returns a dict with keys "read" and "write", each mapping to a dict of counters.
    """
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
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
    return results

def find_bcachefs_instances():
    """Find all bcachefs instances in /sys/fs/bcachefs."""
    base_dir = "/sys/fs/bcachefs"
    if not os.path.exists(base_dir):
        return []
        
    return [d for d in os.listdir(base_dir) 
            if os.path.isdir(os.path.join(base_dir, d)) and d != "by-uuid"]

def analyze_bcachefs_instance(base_dir):
    """Analyze I/O metrics for a single bcachefs instance."""
    # We'll build a nested structure to hold our aggregated metrics.
    # The structure is:
    #
    # group_data = {
    #    <group>: {
    #         "read": {
    #              "totals": { metric: sum_value, ... },
    #              "devices": {
    #                     <device_label>: { metric: value, ... },
    #                     ...
    #              }
    #         },
    #         "write": { similar structure }
    #    },
    #    ...
    # }
    group_data = {}
    overall = {"read": 0, "write": 0}

    # In your system, the devices appear as dev-* directories.
    dev_paths = glob.glob(os.path.join(base_dir, "dev-*"))
    if not dev_paths:
        print(f"No dev-* directories found in {base_dir}!")
        return None

    for dev_path in dev_paths:
        # Each dev-* directory must have a label file.
        label_file = os.path.join(dev_path, "label")
        if not os.path.isfile(label_file):
            continue
        try:
            with open(label_file, "r") as f:
                content = f.read().strip()
                # Expect a label like "ssd.ssd1"
                parts = content.split('.')
                if len(parts) >= 2:
                    group = parts[0].strip()
                    dev_label = parts[1].strip()
                else:
                    group = content.strip()
                    dev_label = content.strip()
        except Exception as e:
            print(f"Error reading {label_file}: {e}")
            continue

        # Look for an io_done file in the same directory.
        io_file = os.path.join(dev_path, "io_done")
        if not os.path.isfile(io_file):
            # If no io_done, skip this device.
            continue

        io_data = parse_io_done(io_file)

        # Initialize the group if not already present.
        if group not in group_data:
            group_data[group] = {
                "read": {"totals": {}, "devices": {}},
                "write": {"totals": {}, "devices": {}}
            }
        # Register this device under the group for both read and write.
        for section in ("read", "write"):
            if dev_label not in group_data[group][section]["devices"]:
                group_data[group][section]["devices"][dev_label] = {}

        # Process each section (read and write).
        for section in ("read", "write"):
            for metric, value in io_data.get(section, {}).items():
                # Update group totals.
                group_totals = group_data[group][section]["totals"]
                group_totals[metric] = group_totals.get(metric, 0) + value

                # Update per-device breakdown.
                dev_metrics = group_data[group][section]["devices"][dev_label]
                dev_metrics[metric] = dev_metrics.get(metric, 0) + value

    # Compute overall totals for read and write across all groups.
    for group in group_data:
        for section in ("read", "write"):
            section_total = sum(group_data[group][section]["totals"].values())
            overall[section] += section_total

    return {
        "group_data": group_data,
        "overall": overall,
        "fs_uuid": os.path.basename(base_dir)
    }

def print_metrics(analysis):
    """Print the metrics analysis in a formatted way."""
    if not analysis:
        return
        
    group_data = analysis["group_data"]
    overall = analysis["overall"]
    fs_uuid = analysis["fs_uuid"]
    
    print(f"=== bcachefs I/O Metrics for {fs_uuid} ===\n")
    
    for group in sorted(group_data.keys()):
        print(f"Group: {group}")
        for section in ("read", "write"):
            section_total = sum(group_data[group][section]["totals"].values())
            overall_section_total = overall[section]
            percent_overall = (section_total / overall_section_total * 100) if overall_section_total > 0 else 0
            print(f"  {section.capitalize()} I/O: {format_bytes(section_total)} ({percent_overall:.2f}% overall)")

            totals = group_data[group][section]["totals"]
            for metric in sorted(totals.keys()):
                metric_total = totals[metric]
                # Build a breakdown string by device for this metric.
                breakdown_entries = []
                for dev_label, metrics in sorted(group_data[group][section]["devices"].items()):
                    dev_value = metrics.get(metric, 0)
                    pct = (dev_value / metric_total * 100) if metric_total > 0 else 0
                    breakdown_entries.append(f"{pct:.2f}% by {dev_label}")
                breakdown_str = ", ".join(breakdown_entries)
                print(f"      {metric:<12}: {format_bytes(metric_total)} ({breakdown_str})")
            print()  # blank line after section
        print()  # blank line after group

def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(description="Analyze bcachefs I/O metrics.")
    parser.add_argument("-u", "--uuid", help="Specific bcachefs UUID to analyze")
    parser.add_argument("-a", "--all", action="store_true", help="Analyze all bcachefs instances")
    parser.add_argument("-j", "--json", action="store_true", help="Output in JSON format")
    args = parser.parse_args()

    if args.uuid:
        # Analyze a specific bcachefs instance
        base_dir = f"/sys/fs/bcachefs/{args.uuid}"
        if not os.path.isdir(base_dir):
            print(f"Error: bcachefs instance {args.uuid} not found!")
            sys.exit(1)
        analysis = analyze_bcachefs_instance(base_dir)
        if analysis:
            if args.json:
                import json
                print(json.dumps(analysis, indent=2))
            else:
                print_metrics(analysis)
    elif args.all:
        # Analyze all bcachefs instances
        instances = find_bcachefs_instances()
        if not instances:
            print("No bcachefs instances found!")
            sys.exit(1)
            
        all_analyses = []
        for instance in instances:
            base_dir = f"/sys/fs/bcachefs/{instance}"
            analysis = analyze_bcachefs_instance(base_dir)
            if analysis:
                all_analyses.append(analysis)
                if not args.json:
                    print_metrics(analysis)
                    print("\n" + "=" * 80 + "\n")
                    
        if args.json:
            import json
            print(json.dumps(all_analyses, indent=2))
    else:
        # If no specific instance or all flag, check if there's only one instance
        instances = find_bcachefs_instances()
        if not instances:
            print("No bcachefs instances found!")
            sys.exit(1)
        elif len(instances) == 1:
            # If there's only one instance, analyze it
            base_dir = f"/sys/fs/bcachefs/{instances[0]}"
            analysis = analyze_bcachefs_instance(base_dir)
            if analysis:
                if args.json:
                    import json
                    print(json.dumps(analysis, indent=2))
                else:
                    print_metrics(analysis)
        else:
            # Multiple instances but no specific one selected
            print("Multiple bcachefs instances found. Please specify one with --uuid or use --all:")
            for instance in instances:
                print(f"  {instance}")
            sys.exit(1)

if __name__ == "__main__":
    main()
