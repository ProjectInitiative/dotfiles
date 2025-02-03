#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.pyyaml age sops
import subprocess
import sys
import tempfile
from pathlib import Path
import argparse
import re

def get_remote_hostname(host):
    """Get the actual hostname from the remote system"""
    try:
        result = subprocess.run(
            ["ssh", host, "hostname"],
            capture_output=True,
            text=True,
            check=True
        )
        # Clean the hostname - remove domain if present and any whitespace
        hostname = result.stdout.strip().split('.')[0].strip()
        return hostname
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
            
    except subprocess.CalledProcessError as e:
        print(f"Error converting SSH key: {e.stderr}")
        sys.exit(1)
    except FileNotFoundError:
        print("ssh-to-age command not found. Please install it first.")
        sys.exit(1)

import yaml

def add_key_to_sops_yaml(age_key, hostname):
    """Add new key to .sops.yaml while preserving existing structure"""
    try:
        with open(".sops.yaml", "r") as f:
            config = yaml.safe_load(f)
            
        # Add key to the users section
        if 'keys' not in config:
            raise Exception("No 'keys' section found in .sops.yaml")

        print(config)
            
        # Find the users list (the one with &users anchor)
        users_list = None
        for item in config['keys']:
            if isinstance(item, dict) and '&users' in item:
                users_list = item['&users']
                break
                
        if users_list is None:
            raise Exception("Could not find &users section in .sops.yaml")
            
        # Add the new key with its anchor
        anchor_name = f"ssh_{hostname}"
        users_list.append(age_key)
        # Note: PyYAML doesn't have direct support for anchors, but we can
        # preserve them by manipulating the string representation later
            
        # Find the secrets rule and add the key reference
        secrets_rule = None
        for rule in config['creation_rules']:
            if 'path_regex' in rule and 'secrets/' in rule['path_regex'] and '.yaml' in rule['path_regex']:
                secrets_rule = rule
                break
                
        if secrets_rule is None:
            raise Exception("Could not find secrets section in creation_rules")
            
        # Ensure the structure exists
        if 'key_groups' not in secrets_rule:
            secrets_rule['key_groups'] = []
        if not secrets_rule['key_groups']:
            secrets_rule['key_groups'] = [{'age': []}]
        if 'age' not in secrets_rule['key_groups'][0]:
            secrets_rule['key_groups'][0]['age'] = []
            
        # Add the reference
        secrets_rule['key_groups'][0]['age'].append(f"*{anchor_name}")
            
        # Now we need to write it back while preserving anchors
        # First, convert to string representation
        yaml_str = yaml.dump(config, default_flow_style=False, sort_keys=False)
            
        # Add the anchor to the key in the users section
        key_escaped = re.escape(age_key)
        yaml_str = re.sub(
            f"- {key_escaped}(\n|$)",
            f"- &{anchor_name} {age_key}\\1",
            yaml_str
        )
            
        # Write back to file
        with open(".sops.yaml", "w") as f:
            f.write(yaml_str)
            
    except Exception as e:
        print(f"Error updating .sops.yaml: {e}")
        sys.exit(1)

def update_secret_files():
    """Re-encrypt all secret files using sops updatekeys"""
    try:
        # Find all yaml files in the secrets directory
        secrets_path = Path("secrets")
        if not secrets_path.exists():
            return
        
        for secret_file in secrets_path.glob("*.yaml"):
            print(f"Updating encryption for {secret_file}")
            subprocess.run(
                ["sops", "updatekeys", str(secret_file)],
                check=True
            )
    except subprocess.CalledProcessError as e:
        print(f"Error updating secret files: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Update SOPS configuration with remote SSH public key')
    parser.add_argument('host', help='Remote host to fetch SSH public key from (e.g., user@hostname)')
    args = parser.parse_args()

    # Check if .sops.yaml exists
    if not Path(".sops.yaml").exists():
        print(".sops.yaml not found in current directory")
        sys.exit(1)

    # Get the remote hostname first
    print(f"Getting hostname from {args.host}...")
    hostname = get_remote_hostname(args.host)
    
    print(f"Retrieving SSH public key from {args.host}...")
    pubkey = get_remote_public_key(args.host)
    
    print("Converting SSH public key to age format...")
    age_key = convert_ssh_to_age(pubkey)
    
    print(f"Updating .sops.yaml with key for {hostname}...")
    add_key_to_sops_yaml(age_key, hostname)
    
    print("Re-encrypting secret files...")
    update_secret_files()
    
    print("Done!")

if __name__ == "__main__":
    main()
