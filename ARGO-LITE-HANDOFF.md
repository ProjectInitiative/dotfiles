# HANDOFF: argo-lite dev container (uncommitted notes — not gitops yet)

> Session notes from 2026-11-11 (juicefs-dev build-out day). Fresh session:
> read this, then the referenced files. Nothing here is committed; the plan
> has NOT been started — only the feasibility assessment was done.

## The idea

Replace the KubeVirt "Argo VM" dev node (which has been painful: 256Gi qcow2
estate image rebuilds per config change, 32Gi reserved RAM, boot/import
machinery) with a **Nix-built container in the argo namespace** ("argo-lite")
that gives an equivalent dev platform:

- persistent home dir on the **juicefs-dev** filesystem (PVC)
- terminal environment from the dotfiles (terminal-env subset), home-manager
  applied **at image build time** (no systemd needed; PID1 = sshd/shell)
- reachable via the existing tailscale ingress-proxy pattern
- runs while astrolabe still exists; JuiceFS is multi-host, so the workspace
  is usable **simultaneously** from astrolabe's FUSE mount and the in-cluster
  PVC during migration. After astrolabe is sold, the workspace lives entirely
  in-cluster on garage-backed storage.

## Verdict (assessed 2026-11-11)

Feasible — most pieces exist as proven patterns in the homelab repo. The
genuinely new work is the Nix container image + the dotfiles container
profile. Effort estimate: gitops pieces = one sitting; Nix image = a session
of iteration.

## The four building blocks

### 1. Dev StorageClass + VSO creds in the argo namespace (NOT STARTED)

- Create `juicefs-dev-sc` StorageClass — clone of `juicefs-sc`
  (`bootstrap/base/juicefs-platform/storage-class.yaml`), pointing at a
  `juicefs-dev-creds` secret in the target namespace.
- VSO projection: mirror the `postgres-cluster` app's vaultSecrets pattern in
  `apps.yaml` (see juicefs-postgres-creds entries) → source
  `k8s/juicefs-dev/config` (bao) → destination `juicefs-dev-creds`.
- Key insight from 2026-11-11: the bao record's keys (`name, storage, bucket,
  access-key, secret-key, metaurl, passphrase`) **already match the juicefs
  CSI secret schema** — `passphrase` is what encrypted-volume mount pods
  need; the RSA PEM itself lives in the meta engine, so NO separate pem
  secret is required for mounts.
- This was deliberately deferred in the juicefs-dev build (see
  homelab `docs/dev-juicefs.md`: "if a dev workload ever needs it, create a
  separate dev-juicefs-sc rather than reusing juicefs-sc").

### 2. Nix container image with the dotfiles container profile (NOT STARTED)

- Template: `generator/cmp-image/image.nix` (`pkgs.dockerTools.buildLayeredImage`)
- Profile: a **container profile** from the dotfiles — home-manager build of
  the terminal subset (`suites.terminal-env`, `cli-apps.zsh`, helix, atuin,
  direnv, dev tools). Home-manager applied at IMAGE BUILD TIME; bake the
  resulting profile into the image. The NixOS-coupled bits (sops, bitwarden,
  browsers, systemd user services) simply aren't enabled in the container
  profile.
- No systemd required — PID1 = sshd + shell.
- UID 1000 (kylepzak) so PVC file ownership matches the astrolabe-side FUSE
  mount (files are owned by uid 1000).
- /nix store is baked read-only: tool changes = image rebuild + Argo sync
  (atomic, arguably the feature). A second PVC mounted at `/nix` for
  in-container builds is a possible later upgrade.

### 3. App manifest `apps/base/argo-lite` (NOT STARTED)

- Deployment, 1 replica, resources ~8C/16Gi, PVC from `juicefs-dev-sc`
  mounted at `/home/kylepzak`, sshd + keys baked in.
- Catalog entry in `apps.yaml` with the vaultSecrets block (same shape as the
  `argo` app's `argo-s3-creds` entry at apps.yaml ~line 1005).

### 4. Reachability — tailscale LB (forgejo pattern)

- `apps/base/forgejo/config/tailscale-lb.yaml`: Service named
  `forgejo-ts-placeholder`, annotation
  `tailscale.com/proxy-group: mc-ingress-proxy`, `loadBalancerClass: tailscale`,
  renamed to its final name by a cluster patch in `clusters/mc.yaml`
  (see the `forgejo` entry's patch block). Copy that pattern for
  `argo-lite-ts-placeholder` → ssh.

## Trade-offs accepted

- No systemd / no `nixos-rebuild`; config changes = image rebuild + Argo sync
- No docker-in-docker unless privileged (out of scope)
- rclone-style ACLs/xattrs: N/A here — the FS data carries whatever the copy
  put there
- kubevirt argo VM can be retired AFTER the container proves out (they can
  coexist: different root disks, both juicefs-backed)

## Migration bonus

JuiceFS multi-host: while astrolabe exists, mount the same FS from both
places; data visible from both. After the sale, the container is the only
access path.

## Current juicefs-dev state (as of 2026-11-11 ~18:30) — the substrate

- FS live and encrypted: 2048-bit passphrase-protected pem (bao
  `k8s/juicefs-dev/pem`), metadata in CNPG `juicefs-dev` DB (role
  `juicefs_dev_user`), owned record `k8s/juicefs-dev/config`
- Endpoints: metaurl = `172.16.4.52:30260` (NodePort — failover-safe,
  bypasses the broken kube-vip VIP, see keel OQ-0052); bucket =
  `http://10.43.202.112:3900/juicefs-dev` (garage ClusterIP — spreads load
  across all 3 garage nodes; PUT latency 162ms → 53ms vs VIP/nodeport)
- Performance config: `synchronous_commit = off` for the juicefs_dev_user
  role (RISK-0044 fsync tax removed); writeback is OPT-IN via
  `JFS_WRITEBACK=1` (dotfiles helper `juicefs-dev-mount`); rclone with
  `--transfers 16` hit 75-280MB/s vs rsync single-stream 157KB/s-9MB/s
- Helpers in dotfiles (`juicefs-dev-env/status/format/mount/umount/gc/
  trash-purge`), run inside `bao-auth` sessions
- **STANDING RULE: any bulk copy to a juicefs mount must exclude
  `.juicefs/**`** (staging feedback loop incident, RISK-0046 context)
- Pending at handoff: rclone copy may still be running; staged-block backlog
  draining; trash purge pending after copy (`juicefs-dev-trash-purge`);
  RISK-0046 compaction (snapshot→restore per node) pending

## Keel records to read in a fresh session

- `RISK-0046` garage meta LMDB bloat/snapshots (partially mitigated)
- `RISK-0044` capstan pool I/O contention (root cause of garage PUT latency)
- `RISK-0045` prod juicefs key at-rest weakness (migration trigger)
- `OQ-0052` kube-vip VIP path drops pod responses (why endpoints avoid VIPs)
- `events/2026.md` 2026-11-11 entries for the full debug chain

## Suggested first session for argo-lite

1. Gitops skeleton: `juicefs-dev-sc` + `juicefs-dev-creds` VSS in
   `apps/base/argo-lite` + app manifest + tailscale LB (one sitting)
2. Nix container profile + image (the real work — iterate)
3. Deploy, ssh in, smoke test, migrate the workspace
4. Retire the argo VM
