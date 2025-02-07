#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p age sops
import subprocess
import sys
import tempfile
from pathlib import Path
import argparse

def get_remote_hostname(host):
    """Get the actual hostname from the remote system"""
    try:
        result = subprocess.run(
            ["ssh", host, "hostname"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip().split('.')[0].strip()
    except subprocess.CalledProcessError as e:
        print(f"Error retrieving remote hostname: {e.stderr}")
        sys.exit(1)

def get_remote_public_key(host):
    """Retrieve the SSH public key from remote host"""
    try:
        result = subprocess.run(
            ["ssh", host, "cat", "/etc/ssh/ssh_host_ed25519_key.pub"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error retrieving remote public key: {e.stderr}")
        sys.exit(1)

def convert_ssh_to_age(pubkey):
    """Convert SSH public key to age format using ssh-to-age"""
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as temp_key:
            temp_key.write(pubkey)
            temp_path = temp_key.name

        try:
            result = subprocess.run(
                ["ssh-to-age", "-i", temp_path],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        finally:
            Path(temp_path).unlink()
    except Exception as e:
        print(f"Error converting SSH key: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Convert remote SSH host key to age format')
    parser.add_argument('host', help='Remote host to fetch SSH public key from (e.g., user@hostname)')
    args = parser.parse_args()

    hostname = get_remote_hostname(args.host)
    pubkey = get_remote_public_key(args.host)
    age_key = convert_ssh_to_age(pubkey)
    
    print(f"&ssh_{hostname} {age_key}")

if __name__ == "__main__":
    main()
