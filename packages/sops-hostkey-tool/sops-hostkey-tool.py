#!/usr/bin/env python3
"""sops-hostkey-tool — one CLI for NixOS host keys end to end.

Subcommands:
  fetch-remote <host>                      ssh to a host, print &ssh_<alias> <age>
  generate-local <alias> [--outdir D]      generate a local keypair + age recipient
  bao-put (--host H | --from-files K PUB | --generate)
          [--bao-path P]                   store a keypair in OpenBao
  bao-get [--bao-path P] [--field F]       print pub / age / private from OpenBao
  inject-image <image.qcow2|img.raw> [--upload]
          [--bao-path P] [--s3-endpoint U --s3-url U]
                                           bake the bao key into a disk image
                                           (kubevirt qcow2, raw, SD images —
                                           the root fs is auto-detected)

Bao layout: KV v2 path (default k8s/argo/ssh-host-key) with fields
ed25519_private / ed25519_public (OpenSSH file contents). Requires an
authenticated `bao`.

Why: NixOS images built with make-disk-image do NOT persist /etc/ssh host
keys (verified 2026-10-22), so every re-import of a VM/SD image
regenerated them and invalidated the sops age recipient. Baking a stable
key into the image before upload fixes it permanently.
"""

import argparse
import subprocess
import sys
import tempfile
import yaml
from pathlib import Path

SOPS_CONFIG = Path(".sops.yaml")
DEFAULT_BAO_PATH = "k8s/argo/ssh-host-key"


def run(cmd, input_text=None, **kwargs):
    """Helper to run a subprocess with error handling."""
    result = subprocess.run(cmd, capture_output=True, text=True, input=input_text, **kwargs)
    if result.returncode != 0:
        print(f"Command failed: {' '.join(cmd)}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def require_bao():
    if not run(["bash", "-c", "command -v bao"]):
        print("ERROR: bao not in PATH (authenticate with: bao auth)", file=sys.stderr)
        sys.exit(1)


### Fetch Mode
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


### Generate Mode
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


### Bao helpers
def bao_get_field(bao_path, field):
    """Return the field value or None if the path/field is absent."""
    result = subprocess.run(
        ["bao", "kv", "get", f"-field={field}", bao_path],
        capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def bao_put(bao_path, priv_path, pub_path):
    run(["bao", "kv", "put", bao_path,
         f"ed25519_private=@{priv_path}",
         f"ed25519_public=@{pub_path}"])


### Image injection (kubevirt qcow2, raw, SD images — any disk with a
### Linux root fs). The root fs is auto-detected: mount each filesystem
### read-only and pick the one that has /etc/ssh.
def _gf_probe(image, dev):
    """True if mounting dev read-only exposes /etc/ssh. Non-fatal."""
    result = subprocess.run(
        ["guestfish", "--ro", "-a", image, "run", ":", "mount", dev, "/", ":", "ls", "/etc/ssh"],
        capture_output=True, text=True)
    return result.returncode == 0


def find_root_fs(image):
    filesystems = run(["guestfish", "--ro", "-a", image, "run", ":",
                       "list-filesystems"])
    candidates = []
    for line in filesystems.splitlines():
        if ":" not in line:
            continue
        dev, fstype = line.rsplit(":", 1)
        if fstype.strip() in ("swap", "unknown", "vfat", "fat", "ntfs"):
            continue
        candidates.append(dev.strip())
    if not candidates:
        print(f"ERROR: no filesystems found in {image}", file=sys.stderr)
        sys.exit(1)
    for dev in candidates:
        if _gf_probe(image, dev):
            return dev
    print(f"ERROR: no filesystem with /etc/ssh found in {image}", file=sys.stderr)
    sys.exit(1)


def inject_key(image, priv_path, pub_path):
    root_dev = find_root_fs(image)
    print(f"root fs: {root_dev}")
    run(["guestfish", "-a", image,
         "run", ":", "mount", root_dev, "/", ":", "mkdir-p", "/etc/ssh",
         ":", "upload", priv_path, "/etc/ssh/ssh_host_ed25519_key",
         ":", "upload", pub_path, "/etc/ssh/ssh_host_ed25519_key.pub"])
    run(["guestfish", "-a", image,
         "run", ":", "mount", root_dev, "/", ":",
         "chmod", "0600", "/etc/ssh/ssh_host_ed25519_key",
         ":", "chmod", "0644", "/etc/ssh/ssh_host_ed25519_key.pub"])
    got = run(["guestfish", "--ro", "-a", image, "run", ":",
               "mount", root_dev, "/", ":",
               "cat", "/etc/ssh/ssh_host_ed25519_key.pub"])
    want = Path(pub_path).read_text().strip()
    if got != want:
        print("ERROR: injection verification mismatch", file=sys.stderr)
        sys.exit(1)
    print(f"OK — key baked into {image} (root fs {root_dev})")


### Main
def main():
    parser = argparse.ArgumentParser(description="sops-hostkey-tool")
    sub = parser.add_subparsers(dest="command", required=True)

    # fetch mode
    fetch = sub.add_parser("fetch-remote", help="print &ssh_<alias> <age> for a remote host")
    fetch.add_argument("host", help="Remote host (e.g. user@hostname)")

    # generate mode
    gen = sub.add_parser("generate-local", help="generate a local keypair + age recipient")
    gen.add_argument("hostname", help="Short hostname alias (for sops.yaml)")
    gen.add_argument("--outdir", default="./generated-keys", help="Where to store keys")

    # bao put
    put = sub.add_parser("bao-put", help="store a keypair in OpenBao")
    src = put.add_mutually_exclusive_group(required=True)
    src.add_argument("--host", help="ssh-fetch the key from this host (user@host)")
    src.add_argument("--from-files", nargs=2, metavar=("KEY", "PUB"),
                     help="existing keypair files")
    src.add_argument("--generate", action="store_true", help="generate a new pair")
    put.add_argument("--bao-path", default=DEFAULT_BAO_PATH)
    put.add_argument("--alias", help="hostname alias (defaults to detected hostname)")

    # bao get
    get = sub.add_parser("bao-get", help="print key material from OpenBao")
    get.add_argument("--bao-path", default=DEFAULT_BAO_PATH)
    get.add_argument("--field", choices=["pub", "age", "private"], default="age")

    # inject image
    inj = sub.add_parser("inject-image", help="bake the bao key into a disk image")
    inj.add_argument("image", help="qcow2 / raw / SD image path")
    inj.add_argument("--upload", action="store_true", help="compress + upload to S3 after injection")
    inj.add_argument("--s3-endpoint", default="http://100.90.143.3:3900")
    inj.add_argument("--s3-url", default="s3://iso/nixos-estate.qcow2")
    inj.add_argument("--bao-path", default=DEFAULT_BAO_PATH)

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

    elif args.command == "bao-put":
        require_bao()
        work = tempfile.mkdtemp()
        if args.host:
            alias = args.alias or get_remote_hostname(args.host)
            priv = Path(work) / "id_ed25519"
            pub = Path(work) / "id_ed25519.pub"
            priv.write_text(run(["ssh", args.host, "cat", "/etc/ssh/ssh_host_ed25519_key"]) + "\n")
            pub.write_text(get_remote_public_key(args.host) + "\n")
            priv.chmod(0o600)
        elif args.from_files:
            alias = args.alias or Path(args.from_files[0]).stem
            priv, pub = args.from_files
        else:
            alias = args.alias or "generated"
            priv, pub, _ = generate_local_key(alias, work)
        bao_put(args.bao_path, priv, pub)
        pub_text = Path(pub).read_text().strip()
        print(f"stored in bao: {args.bao_path}")
        print(f"age recipient: {convert_ssh_to_age(pub_text)}")

    elif args.command == "bao-get":
        require_bao()
        if args.field == "pub":
            print(bao_get_field(args.bao_path, "ed25519_public"))
        elif args.field == "private":
            print(bao_get_field(args.bao_path, "ed25519_private"))
        else:
            pub = bao_get_field(args.bao_path, "ed25519_public")
            if not pub:
                print(f"no key at {args.bao_path}", file=sys.stderr)
                sys.exit(1)
            print(convert_ssh_to_age(pub))

    elif args.command == "inject-image":
        require_bao()
        priv = bao_get_field(args.bao_path, "ed25519_private")
        pub = bao_get_field(args.bao_path, "ed25519_public")
        if not priv or not pub:
            print(f"ERROR: no keypair at {args.bao_path} (use bao-put first)", file=sys.stderr)
            sys.exit(1)
        work = tempfile.mkdtemp()
        priv_f = Path(work) / "id_ed25519"
        pub_f = Path(work) / "id_ed25519.pub"
        priv_f.write_text(priv + "\n")
        pub_f.write_text(pub + "\n")
        priv_f.chmod(0o600)
        inject_key(args.image, str(priv_f), str(pub_f))
        print(f"age recipient: {convert_ssh_to_age(pub)}")
        if args.upload:
            import os
            converted = Path(work) / "converted.qcow2"
            run(["qemu-img", "convert", "-c", "-O", "qcow2", args.image, str(converted)])
            env = os.environ.copy()
            if not env.get("AWS_ACCESS_KEY_ID"):
                env["AWS_ACCESS_KEY_ID"] = run(
                    ["bash", "-c",
                     "kubectl -n argo get secret argo-s3-creds -o jsonpath='{.data.accessKeyId}' | base64 -d"])
                env["AWS_SECRET_ACCESS_KEY"] = run(
                    ["bash", "-c",
                     "kubectl -n argo get secret argo-s3-creds -o jsonpath='{.data.secretKey}' | base64 -d"])
            env.setdefault("AWS_DEFAULT_REGION", "us-east-1")
            result = subprocess.run(["aws", "--endpoint-url", args.s3_endpoint,
                                     "s3", "cp", str(converted), args.s3_url],
                                    env=env, capture_output=True, text=True)
            if result.returncode != 0:
                print(result.stderr, file=sys.stderr)
                sys.exit(1)
            print(f"uploaded to {args.s3_url}")


if __name__ == "__main__":
    main()
