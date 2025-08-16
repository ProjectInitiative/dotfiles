#!/usr/bin/env python3

import subprocess
import sys
import tempfile
import argparse
import yaml
from pathlib import Path

SOPS_CONFIG = Path(".sops.yaml")

def run(cmd, **kwargs):
    """Helper to run a subprocess with error handling."""
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()

### -------------------
### Fetch Mode
### -------------------
def get_remote_hostname(host):
    return run(["ssh", host, "hostname"]).split(".")[0].strip()

def get_remote_public_key(host):
    return run(["ssh", host, "cat", "/etc/ssh/ssh_host_ed25519_key.pub"])

def convert_ssh_to_age(pubkey):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as temp_key:
        temp_key.write(pubkey)
        temp_path = temp_key.name
    try:
        return run(["ssh-to-age", "-i", temp_path])
    finally:
        Path(temp_path).unlink()

### -------------------
### Generate Mode
### -------------------
def generate_local_key(hostname, outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    keyfile = outdir / "ssh_host_ed25519_key"
    pubfile = Path(str(keyfile) + ".pub")

    run(["ssh-keygen", "-t", "ed25519", "-N", "", "-f", str(keyfile)])
    pubkey = pubfile.read_text().strip()
    age_recipient = convert_ssh_to_age(pubkey)

    return str(keyfile), str(pubfile), age_recipient

def update_sops_yaml(alias, age_recipient):
    if not SOPS_CONFIG.exists():
        print(f"No {SOPS_CONFIG}, creating new.")
        config = {"creation_rules": []}
    else:
        config = yaml.safe_load(SOPS_CONFIG.read_text())

    new_rule = {"path_regex": ".*", "key_groups": [{"age": [age_recipient]}]}
    config["creation_rules"].append(new_rule)

    # DOESN'T RESPECT ANCHORS AND ALIASES YET
    # SOPS_CONFIG.write_text(yaml.dump(config))
    print(f"Added {alias} -> {age_recipient} to {SOPS_CONFIG}")

### -------------------
### Main
### -------------------
def main():
    parser = argparse.ArgumentParser(description="sops-hostkey-tool")
    sub = parser.add_subparsers(dest="command")

    # fetch mode
    fetch = sub.add_parser("fetch-remote")
    fetch.add_argument("host", help="Remote host (e.g. user@hostname)")

    # generate mode
    gen = sub.add_parser("generate-local")
    gen.add_argument("hostname", help="Short hostname alias (for sops.yaml)")
    gen.add_argument("--outdir", default="./generated-keys", help="Where to store keys")

    args = parser.parse_args()

    if args.command == "fetch-remote":
        hostname = get_remote_hostname(args.host)
        pubkey = get_remote_public_key(args.host)
        age_key = convert_ssh_to_age(pubkey)
        print(f"&ssh_{hostname} {age_key}")

    elif args.command == "generate-local":
        key, pub, age = generate_local_key(args.hostname, args.outdir)
        print(f"Generated SSH host key at {key}")
        print(f"Age recipient: {age}")
        update_sops_yaml(args.hostname, age)

    else:
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
