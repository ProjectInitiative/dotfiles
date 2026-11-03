# keep-iad-{1,2,3} seed dir — nixos-anywhere --extra-files staging

## What the seed dir is

`--extra-files <dir>` copies **the contents of `<dir>` verbatim onto the
target's filesystem root** at install time. So the tree inside must mirror
the absolute paths the keep role expects on the node:

```
seed/
└── var/
    └── lib/
        ├── infisical/                  ← agent CREDENTIAL dir (0700)
        │   ├── client-id               ← universal-auth Client ID
        │   └── client-secret           ← universal-auth Client Secret
        └── infisical-secrets/          ← agent RENDER dir (0700)
            └── user_password           ← initial password hash
```

## File formats (exact)

| file | content | how to generate |
|---|---|---|
| `var/lib/infisical/client-id` | the Machine Identity Client ID, e.g. `2f4a...` (UUID-ish) | Infisical → Machine Identities → your identity → Client ID (copy) |
| `var/lib/infisical/client-secret` | the Client Secret (long base64-ish string) | same page → Client Secret (shown once at creation) |
| `var/lib/infisical-secrets/user_password` | a yescrypt password **hash** (starts `$y$`) | `mkpasswd -m yescrypt` (type your chosen sudo password) |

**Critical formatting rules:**
- **NO trailing newline** in any file — use `printf '%s'` not `echo`.
  A trailing newline in `user_password` makes every sudo check fail;
  in the client-id/secret it makes agent auth fail.
- Plain text files, UTF-8, no BOM.
- Permissions: `chmod 700` on both dirs, `chmod 600` on all three files.

## What does NOT go in the seed dir

The Infisical secrets (`TAILSCALE_AUTH_KEY`, `K3S_TOKEN`,
`USER_PASSWORD_HASH`) live **server-side** in the Infisical project
(`prod` environment, `/KEEP` folder). The agent fetches and renders them to
`/var/lib/infisical-secrets/` on the node after it authenticates. The seed
dir only carries the identity the agent needs to authenticate + the initial
password hash (because the users-activation script runs before any network
service can reach Infisical).

## Build it (one-time)

```bash
mkdir -p seed/var/lib/infisical seed/var/lib/infisical-secrets
printf '%s' "<CLIENT_ID>"     > seed/var/lib/infisical/client-id
printf '%s' "<CLIENT_SECRET>" > seed/var/lib/infisical/client-secret
mkpasswd -m yescrypt | tr -d '\n' > seed/var/lib/infisical-secrets/user_password
chmod 700 seed/var/lib/infisical seed/var/lib/infisical-secrets
chmod 600 seed/var/lib/infisical/* seed/var/lib/infisical-secrets/*
```

## Provision (per node)

```bash
nixos-anywhere --flake ~/dotfiles-keep-audit#keep-iad-1 --extra-files seed root@<PUBLIC_IP>
```

## Verify (after ~3 min post-boot)

```bash
ssh root@<PUBLIC_IP> 'systemctl is-active infisical-agent tailscaled; ls /var/lib/infisical-secrets/'
# then from a tailnet machine:
ssh kylepzak@keep-iad-1 && sudo -v
```

## Delete after all 3 nodes verify

```bash
rm -rf seed
```
