# Git & Nix Workflow Cheatsheet

This document records useful commands and workflows for managing the dotfiles flake and tracking upstream NixPkgs.

## Nix Flake Management

### Update all inputs except one

To update everything but keep a specific input (e.g., `nixpkgs-catch-up`) pinned:

```bash
nix flake metadata --json | jq -r '.lock.nodes.root.inputs | keys[] | select(. != "nixpkgs-catch-up")' | xargs -I {} nix flake lock --update-input {}
```

### Pin an input to a specific commit

To force an input to a specific Git revision:

```bash
nix flake lock --override-input nixpkgs-catch-up github:nixos/nixpkgs/8435b36f0ee8fd1f97274998443ef66bd810187c
```

---

## Tracking Upstream NixPkgs

### Check which branches contain a commit

Useful for seeing if a fix has landed in `unstable` or `staging`:

```bash
git branch -r --contains <commit-hash>
```

### Check if a commit is in a specific branch (e.g., Stable)

Returns "Yes" if the commit is already merged into the branch:

```bash
git merge-base --is-ancestor <commit-hash> origin/nixos-25.11 && echo "Yes" || echo "No"
```

---

## Git Remote & Cherry-picking Workflow

When you need to pull a specific fix from an upstream PR or a different fork:

1. **Add the remote repository**:

   ```bash
   git remote add upstream-fork https://github.com/someone/nixpkgs.git
   ```

2. **Fetch the remote's branches**:

   ```bash
   git fetch upstream-fork
   ```

3. **Cherry-pick the specific commit**:

   ```bash
   git cherry-pick <commit-hash>
   ```

4. **Remove the temporary remote**:
   ```bash
   git remote remove upstream-fork
   ```

---

## Debugging Nix Evaluation

### Trace evaluation warnings/errors

To find where a warning is coming from, you can force Nix to stop and show a stack trace by setting `NIX_ABORT_ON_WARN=true`.

```bash
# Set the environment variable to turn warnings into errors
export NIX_ABORT_ON_WARN=true

# Build with trace to see the exact file and line number
nix build .#nixosConfigurations.HOST.config.system.build.toplevel --show-trace
```

### Use the REPL to inspect the flake

```bash
nix repl
# Inside REPL:
:lf .
nixosConfigurations.thinkpad.config.environment.systemPackages
```
