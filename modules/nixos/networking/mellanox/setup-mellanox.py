#!/usr/bin/env python3
import json
import subprocess
import argparse
import os
import time # For retries
import sys  # For sys.exit
import shlex # For quoting if necessary, though not strictly used in the final echo

# Configuration for retries
MAX_RETRIES_LINK_UP = 5
RETRY_DELAY_SECONDS_LINK_UP = 3

def run_cmd_for_link_up(command_list, check=True):
    """Helper to run a command (specifically for ip link set up) and handle its output."""
    try:
        # print(f"Running: {' '.join(command_list)}")
        result = subprocess.run(command_list, capture_output=True, text=True, check=check)
        if result.stdout:
            print(f"Stdout: {result.stdout.strip()}")
        # Only print stderr if it was an error that didn't raise CalledProcessError
        if result.stderr and result.returncode != 0 and not check:
            print(f"Stderr: {result.stderr.strip()}")
        return result
    except subprocess.CalledProcessError as e:
        print(f"Command '{' '.join(command_list)}' failed with exit code {e.returncode}")
        if e.stdout: print(f"Stdout: {e.stdout.strip()}")
        if e.stderr: print(f"Stderr: {e.stderr.strip()}")
        raise # Re-raise the exception if check=True
    except FileNotFoundError:
        print(f"Error: Command not found (is iproute2 in PATH?): {command_list[0]}")
        raise

def set_mlnx_port_mode(pci_address, port_number, mode_to_set):
    """
    Sets the mode for a given Mellanox port using bash -c "echo ... > ..."
    as requested due to issues with direct Python file I/O on this sysfs path.
    """
    base_pci_path = f"/sys/bus/pci/devices/{pci_address}"
    # This path construction is based on the original script's behavior
    # and the error occurring at 'mlx4_port2', implying this format is expected.
    full_port_path = f"{base_pci_path}/mlx4_port{port_number}"

    print(f"Attempting to set {full_port_path} mode to '{mode_to_set}' using bash redirection.")

    if not os.path.exists(full_port_path):
        print(f"WARNING: Path {full_port_path} does not exist! Cannot set mode for port {port_number}.")
        return False

    # 1. Optional: Check current mode first for idempotency (read directly)
    try:
        with open(full_port_path, 'r') as f:
            current_mode = f.read().strip()
        if current_mode == mode_to_set:
            print(f"Port {full_port_path} (read directly) already in mode '{mode_to_set}'. Skipping bash echo.")
            return True
    except IOError as e:
        print(f"Info: Could not read current mode from {full_port_path} before writing: {e}. Proceeding with write attempt.")
    except Exception as e:
        print(f"Info: Unexpected error reading current mode from {full_port_path}: {e}. Proceeding with write attempt.")

    # 2. Use bash -c echo with the original script's path escaping logic
    try:
        # This escaping logic is taken directly from the user's original script snippet.
        escaped_path_for_shell_command = full_port_path.replace(":", r"\:")
        
        # The mode_to_set ("eth", "ib") is simple and doesn't need shlex.quote here.
        shell_command_str = f"echo {mode_to_set} > {escaped_path_for_shell_command}"
        cmd_list = ["bash", "-c", shell_command_str]
        
        # Log the command string as bash would see it (best effort for complex commands)
        print(f"Running: bash -c '{shell_command_str}'")
        
        result = subprocess.run(cmd_list, capture_output=True, text=True, check=False)

        if result.returncode == 0:
            # Even if returncode is 0, stderr might contain warnings from the driver/shell
            if result.stderr:
                print(f"Bash stderr (on success, retcode 0): {result.stderr.strip()}")
            print(f"Bash echo command for '{shell_command_str}' completed successfully.")
        else:
            print(f"ERROR: Bash echo command failed with return code {result.returncode}.")
            if result.stdout: print(f"Stdout: {result.stdout.strip()}")
            if result.stderr: print(f"Stderr: {result.stderr.strip()}")
            return False # Command execution failed

        # 3. Verify by reading back from the actual (unescaped) sysfs path
        time.sleep(0.2) # Give a moment for the change to apply and be readable
        try:
            with open(full_port_path, 'r') as f:
                verified_mode = f.read().strip()
            if verified_mode == mode_to_set:
                print(f"Verified: Mode for {full_port_path} is now '{verified_mode}'.")
                return True
            else:
                # This can happen if the echo command didn't actually change the mode
                # or if the escaped_path_for_shell_command was misinterpreted by bash
                # and it wrote somewhere else or failed silently before this check.
                print(f"ERROR: Mode verification failed for {full_port_path}. Expected '{mode_to_set}', got '{verified_mode}'.")
                return False
        except IOError as e:
            print(f"ERROR: Could not read back mode from {full_port_path} for verification: {e}")
            return False
        except Exception as e:
            print(f"ERROR: Unexpected error verifying mode from {full_port_path}: {e}")
            return False

    except Exception as e:
        print(f"Unexpected exception during 'set_mlnx_port_mode' for {full_port_path}: {str(e)}")
        return False

def set_link_up(nic_name):
    """Brings a network interface up, with retries."""
    print(f"Attempting to bring up interface: {nic_name}")
    for attempt in range(MAX_RETRIES_LINK_UP):
        try:
            # run_cmd_for_link_up(["ip", "link", "show", nic_name]) # Optional: Check if exists first
            run_cmd_for_link_up(["ip", "link", "set", nic_name, "up"])
            print(f"Successfully activated {nic_name} (ip link set {nic_name} up).")
            return True # Success
        except subprocess.CalledProcessError as e:
            # This error often means the interface doesn't exist or another issue
            print(f"Attempt {attempt + 1}/{MAX_RETRIES_LINK_UP}: 'ip link set {nic_name} up' failed. Stderr: {e.stderr.strip()}")
        except FileNotFoundError:
             print(f"Attempt {attempt + 1}/{MAX_RETRIES_LINK_UP}: 'ip' command not found. Ensure iproute2 is in PATH.")
             # This is a fatal error for this function's purpose if iproute2 is missing
             return False
        except Exception as e:
            print(f"Attempt {attempt + 1}/{MAX_RETRIES_LINK_UP}: Unexpected error bringing up {nic_name}: {str(e)}")

        if attempt < MAX_RETRIES_LINK_UP - 1:
            print(f"Retrying in {RETRY_DELAY_SECONDS_LINK_UP} seconds...")
            time.sleep(RETRY_DELAY_SECONDS_LINK_UP)
        else:
            print(f"ERROR: Failed to bring up {nic_name} after {MAX_RETRIES_LINK_UP} attempts.")
            return False # Failure after all retries

def main():
    parser = argparse.ArgumentParser(description='Configure Mellanox network cards')
    parser.add_argument('--config', '-c',
        help='Path to JSON configuration file',
        required=True)
    args = parser.parse_args()

    if not os.path.exists(args.config):
        print(f"ERROR: Configuration file not found: {args.config}")
        sys.exit(1)

    critical_failure_occurred = False

    try:
        with open(args.config) as json_file:
            data = json.load(json_file)
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from {args.config}: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading config file {args.config}: {e}")
        sys.exit(1)

    for interface_config in data.get("interfaces", []):
        device_info = interface_config.get('device', 'N/A')
        pci_address = interface_config.get("pci_address")

        print(f"\nConfiguring Mellanox device: {device_info} at PCI: {pci_address or 'N/A'}")

        if not pci_address:
            print("WARNING: Skipping interface entry due to missing 'pci_address'.")
            continue

        # Set Mellanox port modes
        mlnx_port_mode = interface_config.get("mode", "eth") # Default to "eth" if not specified
        for mlnx_port_num in interface_config.get("mlnx_ports", []):
            if not set_mlnx_port_mode(pci_address, mlnx_port_num, mlnx_port_mode):
                print(f"ERROR: Failed to set mode for PCI {pci_address}, port {mlnx_port_num}.")
                critical_failure_occurred = True # Setting port mode is critical

        # Bring up specified physical NICs
        # The 'nics' field in JSON should be 'physical_nics' as per the updated .nix module
        for nic_name in interface_config.get("physical_nics", []): # Ensure JSON uses "physical_nics"
            # This script should ONLY bring up physical interfaces.
            # Bonded interfaces (bond0) or bridges (vmbrX) should be managed by
            # systemd-networkd or NetworkManager based on NixOS configuration.
            if nic_name.startswith("bond") or nic_name.startswith("vmbr"):
                print(f"INFO: Skipping {nic_name} as it appears to be a virtual interface. It should be managed by standard networking services.")
                continue

            if not set_link_up(nic_name):
                print(f"ERROR: Failed to bring up physical NIC {nic_name} for PCI {pci_address}.")
                critical_failure_occurred = True # Bringing up a specified physical NIC is critical

        print(f"Finished processing configuration for PCI: {pci_address}")

    if critical_failure_occurred:
        print("\nOne or more critical operations failed during Mellanox setup. Exiting with error.")
        sys.exit(1)
    else:
        print("\nAll configured Mellanox interfaces processed successfully.")
        sys.exit(0)

if __name__ == "__main__":
    main()
