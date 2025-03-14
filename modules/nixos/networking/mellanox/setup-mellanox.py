#!/usr/bin/env python3
# importing the module
import json
import subprocess
import argparse
import os
import shlex

def main():
    parser = argparse.ArgumentParser(description='Configure Mellanox network cards')
    parser.add_argument('--config', '-c', 
        help='Path to JSON configuration file (default: /etc/mellanox/mellanox-interfaces.json)',
        default='/etc/mellanox/mellanox-interfaces.json')
    args = parser.parse_args()
    
    # Opening JSON file
    with open(args.config) as json_file:
        data = json.load(json_file)
        for interface in data["interfaces"]:
            # Get the base PCI path - no escaping needed here
            base_pci_path = f"/sys/bus/pci/devices/{interface['pci_address']}"
            
            for mlnx_port in interface["mlnx_ports"]:
                # Construct the full port path - no escaping needed in the path construction
                full_port_path = f"{base_pci_path}/mlx4_port{mlnx_port}"
                
                print(f"Changing {full_port_path} mode to {interface['mode']}")
                
                # Check if the path exists
                if not os.path.exists(full_port_path):
                    print(f"WARNING: Path {full_port_path} does not exist!")
                    continue
                
                try:
                    # For NixOS compatibility, we need to properly escape the path for shell redirection
                    # The escaped path is only used in the shell command
                    escaped_path = full_port_path.replace(":", r"\:")
                    
                    # Use bash explicitly to ensure consistent behavior
                    cmd = ["bash", "-c", f"echo {interface['mode']} > {escaped_path}"]
                    print(f"Running: {' '.join(cmd)}")
                    
                    # Execute with shell=False since we're directly invoking bash
                    result = subprocess.run(cmd, capture_output=True, text=True)
                    
                    if result.returncode != 0:
                        print(f"Error: {result.stderr}")
                    else:
                        print(f"Successfully wrote '{interface['mode']}' to {full_port_path}")
                        
                except Exception as e:
                    print(f"Could not write to {full_port_path}: {str(e)}")
                    
            for nic in interface["nics"]:
                try:
                    # Use bash for consistent behavior
                    cmd = ["bash", "-c", f"ip link set {nic} up"]
                    print(f"Running: {' '.join(cmd)}")
                    result = subprocess.run(cmd, capture_output=True, text=True)
                    
                    if result.returncode == 0:
                        print(f"Successfully activated {nic}")
                    else:
                        print(f"Could not activate {nic}: {result.stderr}")
                        
                except Exception as e:
                    print(f"Error running command: {str(e)}")
                    
            print(f"Configured interface: {interface}")

if __name__ == "__main__":
    main()
