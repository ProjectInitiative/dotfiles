
    #!/usr/bin/env python3

    import argparse
    import json
    import os
    import subprocess
    import logging
    import sys

    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

    # Helper function to convert JSON to Nix format
    def json_to_nix(obj, indent=2, level=1):
        indent_str = " " * indent * level
        prev_indent_str = " " * indent * (level - 1)
        
        if isinstance(obj, dict):
            if not obj:
                return "{ }"
            
            result = "{\n"
            items = []
            
            for k, v in obj.items():
                item = f"{indent_str}{k} = {json_to_nix(v, indent, level + 1)};"
                items.append(item)
            
            result += "\n".join(items)
            result += f"\n{prev_indent_str}}}"
            return result
            
        elif isinstance(obj, list):
            if not obj:
                return "[ ]"
            
            result = "[\n"
            items = []
            
            for item in obj:
                items.append(f"{indent_str}{json_to_nix(item, indent, level + 1)}")
            
            result += "\n".join(items)
            result += f"\n{prev_indent_str}]"
            return result
            
        elif isinstance(obj, str):
            # Escape quotes and newlines in strings
            escaped = obj.replace('"', '\\"').replace("\n", "\\n")
            return f'"{escaped}"'
            
        elif obj is True:
            return "true"
            
        elif obj is False:
            return "false"
            
        elif obj is None:
            return "null"
            
        else:
            return str(obj)  # For numbers and other types

    class DriveInfoCollector:
        # Define LSBLK command for detailed block device info
        LSBLK_DISCOVER_CMD = [
            "lsblk",
            "--all",
            "-po",
            "MODEL,NAME,PATH,ROTA,TRAN,SERIAL,SIZE,TYPE,FSTYPE,MOUNTPOINT",
            "--json",
        ]

        def __init__(self, args):
            self.args = args
            self.host = args.host
            self.ssh_user = args.user or os.environ.get("USER")
            self.remote = self.host is not None

        # Run commands either locally or remotely
        def run_command(self, cmd):
            cmd_str = " ".join(cmd)
            logging.debug(f"Running command: {cmd_str}")
            
            if self.remote:
                ssh_cmd = ["ssh", f"{self.ssh_user}@{self.host}", cmd_str]
                return subprocess.check_output(ssh_cmd).decode("utf-8")
            else:
                return subprocess.check_output(cmd).decode("utf-8")

        # Get block devices and classify them
        def get_block_devices(self):
            output = self.run_command(self.LSBLK_DISCOVER_CMD)
            drives_dict = json.loads(output)
            block_devices = []

            for block_device in drives_dict["blockdevices"]:
                # Skip all non-disk devices
                if block_device["type"] != "disk":
                    continue
                
                # Classify block device
                self._classify_block_class(block_device)
                
                # Only include devices with a serial number
                if block_device.get("serial"):
                    block_devices.append(block_device)

            return block_devices

        # Classify block devices by type
        def _classify_block_class(self, block_device):
            if not block_device["rota"]:
                if block_device.get("tran") == "nvme":
                    block_class = "nvme"
                    tier = "hot"
                else:
                    block_class = "ssd"
                    tier = "warm"
            else:
                block_class = "hdd"
                tier = "cold"

            block_device["tier"] = tier
            block_device["block_class"] = block_class

        # Get drive by-id paths
        def get_drive_by_id_paths(self):
            cmd = ["ls", "-la", "/dev/disk/by-id"]
            try:
                output = self.run_command(cmd)
                return output
            except subprocess.CalledProcessError:
                logging.error("Failed to get drive by-id paths")
                return ""

        # Parse by-id links to match with block devices
        def parse_by_id_links(self, by_id_output):
            by_id_map = {}
            # First pass: collect all entries
            all_entries = {}
            for line in by_id_output.splitlines():
                parts = line.split()
                if len(parts) >= 11 and '->' in line:
                    id_path = parts[8]
                    target = parts[10].split('/')[-1]
                    
                    # Skip partition entries for now, we'll handle them later
                    if not target.endswith(('p1', 'p2', 'p3', '1', '2', '3')):
                        # Initialize if not exists
                        if target not in all_entries:
                            all_entries[target] = []
                        all_entries[target].append(id_path)
            
            # Second pass: prioritize entries
            for target, paths in all_entries.items():
                # Prioritize ata- paths first
                ata_paths = [p for p in paths if p.startswith('ata-')]
                if ata_paths:
                    by_id_map[target] = f"/dev/disk/by-id/{ata_paths[0]}"
                    continue
                
                # Then prioritize nvme paths with model and serial
                nvme_model_paths = [p for p in paths if p.startswith('nvme-') and '_' in p and not p.endswith(('_1', '_2'))]
                if nvme_model_paths:
                    by_id_map[target] = f"/dev/disk/by-id/{nvme_model_paths[0]}"
                    continue
                
                # Then any nvme path
                nvme_paths = [p for p in paths if p.startswith('nvme-')]
                if nvme_paths:
                    by_id_map[target] = f"/dev/disk/by-id/{nvme_paths[0]}"
                    continue
                
                # Fallback to wwn paths or whatever is available
                by_id_map[target] = f"/dev/disk/by-id/{paths[0]}"
            
            # Now get partition entries
            for line in by_id_output.splitlines():
                parts = line.split()
                if len(parts) >= 11 and '->' in line:
                    id_path = parts[8]
                    target = parts[10].split('/')[-1]
                    
                    # Only handle partitions and only if we don't have them already
                    if target.endswith(('p1', 'p2', 'p3', '1', '2', '3')) and target not in by_id_map:
                        # Match partitions to same naming scheme as their parent
                        parent_device = target.rstrip('p123').rstrip('123')
                        if parent_device in by_id_map:
                            parent_path = by_id_map[parent_device].split('/')[-1]
                            parent_prefix = parent_path.split('-')[0]  # Get prefix (ata, nvme, etc)
                            
                            # Find matching partition path with same prefix
                            matching_paths = [p for p in by_id_output.splitlines() 
                                             if target in p and parent_prefix in p]
                            
                            if matching_paths:
                                partition_path = matching_paths[0].split()[8]
                                by_id_map[target] = f"/dev/disk/by-id/{partition_path}"
                            else:
                                by_id_map[target] = f"/dev/disk/by-id/{id_path}"
                        else:
                            by_id_map[target] = f"/dev/disk/by-id/{id_path}"
            
            return by_id_map

        # Generate disko config structure
        def generate_disko_config(self, block_devices, by_id_map):
            disko_config = {"disk": {}}
            
            # Counters for each device type
            counters = {"nvme": 0, "ssd": 0, "hdd": 0}
            
            for device in block_devices:
                device_name = device["name"].split('/')[-1]
                device_type = device["block_class"]
                full_path = by_id_map.get(device_name, device["path"])
                
                # Increment type-specific counter
                counters[device_type] += 1
                
                # Create a device identifier with type-specific counter
                device_id = f"{device_type}{counters[device_type]}"
                
                disko_config["disk"][device_id] = {
                    "type": "disk",
                    "device": full_path,
                    "content": {
                        "type": "bcachefs_member",
                        "pool": "pool",
                        "label": f"{device_type}.{device_id}"
                    }
                }
            
            # Add bcachefs pool configuration
            disko_config["bcachefs"] = {
                "pool": {
                    "type": "bcachefs",
                    "mountpoint": "/mnt/bcachefs",
                    "formatOptions": ["--compression=lz4"],
                    "mountOptions": [
                        "verbose",
                        "degraded"
                    ]
                }
            }
            
            return disko_config

        # Main method to collect all info and generate config
        def collect_and_generate(self):
            # Get block devices
            block_devices = self.get_block_devices()
            
            # Get by-id paths
            by_id_output = self.get_drive_by_id_paths()
            by_id_map = self.parse_by_id_links(by_id_output)
            
            # Create full drive info
            drive_info = {
                "block_devices": block_devices,
                "by_id_map": by_id_map
            }
            
            # Generate disko config
            disko_config = self.generate_disko_config(block_devices, by_id_map)
            
            result = {
                "drive_info": drive_info,
                "disko_config": disko_config
            }
            
            return result

    def main():
        parser = argparse.ArgumentParser(description="Collect drive info from a local or remote host")
        parser.add_argument("-H", "--host", help="Remote host to connect to")
        parser.add_argument("-u", "--user", help="SSH user for remote connection")
        parser.add_argument("-o", "--output", help="Output file for JSON (default: stdout)")
        parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")
        parser.add_argument("-n", "--nix", action="store_true", help="Output disko config in Nix format")
        
        args = parser.parse_args()
        
        if args.verbose:
            logging.getLogger().setLevel(logging.DEBUG)
        
        drive_collector = DriveInfoCollector(args)
        result = drive_collector.collect_and_generate()
        
        if args.nix:
            # Output just the disko config in Nix format
            nix_output = "{\n"
            nix_output += "  disko.devices = " + json_to_nix(result["disko_config"]) + ";\n"
            nix_output += "}"
            
            if args.output:
                with open(args.output, 'w') as f:
                    f.write(nix_output)
                print(f"Nix configuration written to {args.output}")
            else:
                print(nix_output)
        else:
            # Format JSON with indentation for readability
            json_output = json.dumps(result, indent=2)
            
            if args.output:
                with open(args.output, 'w') as f:
                    f.write(json_output)
                print(f"Results written to {args.output}")
            else:
                print(json_output)

    if __name__ == "__main__":
        main()
