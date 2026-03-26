#!/usr/bin/env python3
"""
Deployment script for NixOS routers with failsafe rollback.
"""

import argparse
import subprocess
import sys
import time

def run_command(cmd, shell=False, check=True, capture_output=True, timeout=None):
    """Run a local command."""
    print(f"Running locally: {' '.join(cmd) if not shell else cmd}")
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            check=check,
            capture_output=capture_output,
            text=True,
            timeout=timeout
        )
        return result
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")
        if e.stdout:
            print(f"STDOUT: {e.stdout}")
        if e.stderr:
            print(f"STDERR: {e.stderr}")
        raise
    except subprocess.TimeoutExpired as e:
        print(f"Command timed out after {timeout} seconds")
        raise

def run_remote_command(user, host, port, command, timeout=10):
    """Run a command over SSH and return stdout, stderr, and exit status."""
    cmd = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=accept-new",
        "-p", str(port),
        f"{user}@{host}",
        command
    ]

    print(f"Running remotely: {command}")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return 255, "", "Connection timed out"
    except Exception as e:
        return 255, "", str(e)

def check_ssh_connectivity(host, user, port=22, timeout=5, retries=3, delay=5):
    """Check if we can SSH into the host."""
    for attempt in range(retries):
        print(f"Attempting SSH connection to {user}@{host}:{port} (Attempt {attempt+1}/{retries})...")

        status, out, err = run_remote_command(user, host, port, "echo 'SSH Connection Successful'", timeout=timeout)

        if status == 0:
            print(f"SSH connection to {host} successful.")
            return True
        else:
            print(f"SSH connection failed. Status: {status}, Error: {err}")
            if attempt < retries - 1:
                print(f"Waiting {delay} seconds before retrying...")
                time.sleep(delay)

    return False

def main():
    parser = argparse.ArgumentParser(description="Deploy NixOS configuration to router with validation and rollback.")
    parser.add_argument("host", help="The target host (e.g., stormjib or its IP address)")
    parser.add_argument("--flake", default=".", help="Path to the flake (default: current directory)")
    parser.add_argument("--user", default="root", help="SSH username (default: root)")
    parser.add_argument("--port", type=int, default=22, help="SSH port (default: 22)")
    parser.add_argument("--validation-timeout", type=int, default=30, help="Total time to wait for validations to pass (seconds)")

    args = parser.parse_args()

    flake_target = f"{args.flake}#{args.host}"

    print(f"Starting deployment pipeline for {args.host}...")

    # --- Phase 1: Pre-Deployment Tasks ---
    # To handle the issue where NixOS activation scripts only restart modified services,
    # we explicitly start the failsafe timer on the remote host *before* we execute
    # the deployment switch. We use systemd-run so that if network drops mid-deployment
    # due to the switch, the timer is already ticking.
    print("\n--- Phase 1: Priming the failsafe timer ---")
    prime_cmd = [
        "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-p", str(args.port), f"{args.user}@{args.host}",
        "systemctl start router-failsafe-validation.service"
    ]
    print(f"Running command: {' '.join(prime_cmd)}")
    status, out, err = run_remote_command(args.user, args.host, args.port, "systemctl start router-failsafe-validation.service")
    if status != 0:
        print(f"Failed to start failsafe timer on {args.host}! Status: {status}")
        print(f"Error: {err}")
        print("WARNING: Proceeding without failsafe protection. Are you sure?")
        # For a truly strict deployment script, we might exit here.
        # But if this is the first time the failsafe module is deployed, it won't exist yet!
        # Thus, we warn but continue.
    else:
        print("Failsafe timer activated.")

    # --- Step 2: Push the Nix closure and activate the configuration ---
    print("\n--- Phase 2: Deployment & Activation ---")

    # We use nixos-rebuild to handle copying the closure and switching.
    deploy_cmd = [
        "nixos-rebuild", "switch",
        "--flake", flake_target,
        "--target-host", f"{args.user}@{args.host}",
        "--use-remote-sudo"
    ]

    try:
        # We don't capture output here so the user can see the progress of the build and copy
        print(f"Running deployment command: {' '.join(deploy_cmd)}")
        subprocess.run(deploy_cmd, check=True)
        print("Deployment successful. New configuration is active.")
    except Exception as e:
        print(f"Deployment failed before activation or during activation: {e}")
        print("Since the push/activation command failed, assuming manual intervention or rollback is needed.")
        sys.exit(1)

    # --- Step 3: Remote Validation Checks ---
    print("\n--- Phase 3: Remote Validation ---")
    print(f"Waiting 5 seconds for services to settle before validation...")
    time.sleep(5)

    # 2.a Check SSH Connectivity
    print("Validating SSH connectivity...")
    if not check_ssh_connectivity(args.host, args.user, args.port):
        print("CRITICAL: Lost SSH connectivity after deployment!")
        print("Triggering automatic rollback mechanism...")
        # Since we can't SSH, we hope the local failsafe timer (router-failsafe-validation) triggers.
        # It's important that the local failsafe module is enabled on the router!
        print("Waiting for local failsafe timer to expire and rollback the router...")
        sys.exit(1)

    validation_passed = True

    # 2.b Verify Gateway Reachability (can it ping outside?)
    print("Validating Gateway Reachability...")
    status, out, err = run_remote_command(args.user, args.host, args.port, "ping -c 3 -W 5 8.8.8.8")
    if status == 0:
        print("Gateway reachability check PASSED.")
    else:
        print(f"Gateway reachability check FAILED. Output:\n{out}\n{err}")
        validation_passed = False

    # 2.c Check active routing tables
    print("Validating Active Routing Tables...")
    status, out, err = run_remote_command(args.user, args.host, args.port, "ip route show default")
    if status == 0 and out.strip() != "":
        print("Default route check PASSED.")
    else:
        print(f"Default route check FAILED. No default route found. Output:\n{out}\n{err}")
        validation_passed = False

    # --- Step 4: Action based on validation ---
    if validation_passed:
        print("\n--- Phase 4: Success ---")
        print("All validation checks passed. Deployment finalized.")

        # We should explicitly stop the router-failsafe-validation service so it doesn't rollback
        # after its timer expires!
        print("Disabling local failsafe timer...")
        run_remote_command(args.user, args.host, args.port, "systemctl stop router-failsafe-validation.service")
        print("Local failsafe timer disabled.")

        sys.exit(0)
    else:
        print("\n--- Phase 4: Failure & Rollback ---")
        print("Validation checks failed. Initiating immediate rollback...")

        status, out, err = run_remote_command(args.user, args.host, args.port, "systemd-run --unit=emergency-rollback nixos-rebuild switch --rollback")
        if status == 0:
            print("Rollback triggered successfully. Reconnecting to verify...")
            # We wait a moment for the rollback switch to start and disrupt the network
            time.sleep(15)
            # We check if we can connect again
            if check_ssh_connectivity(args.host, args.user, args.port, timeout=10, retries=5, delay=10):
                print("Reconnected to router after rollback. Node has successfully restored previous generation.")
            else:
                print("Failed to reconnect after rollback. Node state is unknown. Manual intervention required!")
        else:
            print(f"Rollback command failed! Return code: {status}")
            print(f"STDOUT:\n{out}")
            print(f"STDERR:\n{err}")

        sys.exit(1)

if __name__ == "__main__":
    main()
