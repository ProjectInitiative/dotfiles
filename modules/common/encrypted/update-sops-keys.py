#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.pyyaml

import argparse
import subprocess
import yaml
from pathlib import Path

def get_host_age_pubkey(host, user, ssh_key_path):
    ssh_cmd = [
        "ssh",
        "-i", str(ssh_key_path),
        "-o", "StrictHostKeyChecking=no",
        f"{user}@{host}",
        "cat", "/etc/ssh/ssh_host_ed25519_key.pub"
    ]
    
    try:
        result = subprocess.run(
            ssh_cmd,
            check=True,
            capture_output=True,
            text=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Failed to retrieve host key: {e.stderr}")

def update_sops_yaml(sops_path, new_key):
    sops_path = Path(sops_path)
    if not sops_path.exists():
        raise FileNotFoundError(f"{sops_path} not found")
    
    with open(sops_path) as f:
        config = yaml.safe_load(f) or {}
    
    creation_rules = config.get("creation_rules", [{}])
    if not creation_rules:
        creation_rules = [{}]
    
    current_keys = creation_rules[0].get("age", "").split(",")
    current_keys = [k.strip() for k in current_keys if k.strip()]
    
    if new_key not in current_keys:
        current_keys.append(new_key)
        creation_rules[0]["age"] = ", ".join(current_keys)
        config["creation_rules"] = creation_rules
        
        with open(sops_path, "w") as f:
            yaml.dump(config, f, default_flow_style=False)
        return True
    return False

def reencrypt_secrets():
    try:
        subprocess.run(["sops", "--rotate", "--in-place", "secrets.yaml"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Re-encryption failed: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Update SOPS configuration with new host key")
    parser.add_argument("--host", required=True, help="New host IP/hostname")
    parser.add_argument("--user", default="root", help="SSH user")
    parser.add_argument("--ssh-key", required=True, help="Path to SSH private key for authentication")
    parser.add_argument("--sops-file", default=".sops.yaml", help="Path to .sops.yaml file")
    
    args = parser.parse_args()
    
    try:
        pubkey = get_host_age_pubkey(args.host, args.user, args.ssh_key)
        updated = update_sops_yaml(args.sops_file, pubkey)
        
        if updated:
            print("Updating secrets with new key...")
            reencrypt_secrets()
            print("Successfully updated SOPS configuration and re-encrypted secrets")
        else:
            print("Key already present in SOPS configuration")
    except Exception as e:
        print(f"Error: {str(e)}")
        exit(1)
