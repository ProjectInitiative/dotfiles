# Migration from Snowfall-Lib to Flake-Parts

This document tracks the progress of migrating the project from `snowfall-lib` to a standard `flake-parts` based structure.

## Goals
- Remove `snowfall-lib` dependency.
- Switch to `flake-parts` for flake structure.
- Replace "magic" module loading with explicit or locally controlled logic.
- Remove custom library helpers (`mkOpt`, `mkBoolOpt`, `enabled`) in favor of standard `lib.mkOption` / `lib.mkEnableOption`.
- Ensure the `thinkpad` system builds correctly.

## Completed Tasks

### Flake & Library Structure
- [x] Created `remove-snowfall-lib` branch.
- [x] Refactored `flake.nix`:
    - Removed `snowfall-lib` input.
    - Added `flake-parts` input.
    - Rewrote `outputs` to use `flake-parts.lib.mkFlake`.
    - Defined `nixosConfigurations.thinkpad` manually.
- [x] Created `lib/default.nix`:
    - Combined helper functions (`fs` utilities and module helpers).
    - Added `get-common-modules` to recursively import modules (mimicking Snowfall's availability).
    - Note: `mkOpt`/`mkBoolOpt` were temporarily added here but are being phased out from modules.

### Module Refactoring
The following modules have been refactored to remove `mkOpt`, `mkBoolOpt`, `enabled`, and `with lib.${namespace}`:

- [x] `modules/common/suites/development/default.nix`
- [x] `modules/home/home/default.nix`
- [x] `modules/home/tools/git/default.nix`
- [x] `modules/nixos/gui/gnome/default.nix`
- [x] `modules/nixos/hosts/lightship/default.nix`
- [x] `modules/nixos/services/k3s/default.nix` (Was already clean)
- [x] `modules/nixos/services/k8s/default.nix`
- [x] `modules/common/system/fonts/default.nix`

## Remaining Tasks

### 1. Refactor Remaining Modules
The following modules still use Snowfall-style helpers and need to be updated to standard NixOS syntax:

**System & Core:**
- [x] `modules/nixos/system/locale/default.nix` (Found, pending edit)
- [x] `modules/common/encrypted/default.nix`
- [x] `modules/common/settings/default.nix`
- [x] `modules/common/settings/graphical/default.nix`

**Hosts & Hardware:**
- [x] `modules/nixos/hosts/base-container/default.nix`
- [x] `modules/nixos/hosts/base-vm/default.nix`
- [x] `modules/nixos/hosts/capstan/default.nix`
- [x] `modules/nixos/hosts/cargohold/default.nix`
- [x] `modules/nixos/hosts/lighthouse/default.nix`
- [x] `modules/nixos/hosts/live-usb/default.nix`
- [x] `modules/nixos/hosts/masthead/default.nix`
- [x] `modules/nixos/hosts/masthead/stormjib/default.nix`
- [x] `modules/nixos/hosts/router/default.nix` (and associated router/*.nix files)

**Services:**
- [x] `modules/nixos/services/attic-client/default.nix`
- [x] `modules/nixos/services/attic-server/default.nix`
- [x] `modules/nixos/services/bcachefs-*/default.nix` (Multiple files)
- [x] `modules/nixos/services/eternal-terminal/default.nix`
- [x] `modules/nixos/services/health-reporter/default.nix`
- [x] `modules/nixos/services/juicefs/default.nix`
- [x] `modules/nixos/services/monitoring/default.nix`
- [x] `modules/nixos/services/s3-sync.nix`
- [x] `modules/nixos/services/sync-host/default.nix`

**CLI Apps & Tools (Home Manager):**
- [x] `modules/home/cli-apps/*/default.nix` (atuin, bat, eza, helix, nix, ripgrep, zellij, zoxide, zsh)
- [x] `modules/home/tools/*/default.nix` (aider, alacritty, ansible, direnv, ghostty, k8s)
- [ ] `modules/home/browsers/*/default.nix` (chrome, chromium, firefox, ladybird, librewolf, tor)
- [ ] `modules/home/security/*/default.nix` (gpg, sops)
- [ ] `modules/home/suites/*/default.nix` (backup, digital-creation, messengers, terminal-env)
- [ ] `modules/home/user/default.nix`
- [ ] `modules/home/users/kylepzak/default.nix`

**System Components:**
- [ ] `modules/nixos/system/bcachefs-*/default.nix`
- [ ] `modules/nixos/system/console-info/ip-display/default.nix`
- [ ] `modules/nixos/system/displaylink/default.nix`
- [ ] `modules/nixos/system/nix-config/default.nix`
- [ ] `modules/nixos/virtualization/*/default.nix` (docker, podman)
- [ ] `modules/nixos/disko/*/default.nix`

### 2. Verify and Build
- [ ] Run `nixos-rebuild build --flake .#thinkpad` to verify the refactor.
- [ ] Fix any remaining syntax errors or missing imports.

### 3. Cleanup
- [ ] Remove `mkOpt`, `mkBoolOpt` from `lib/default.nix` once all modules are updated.
- [ ] Verify `flake.lock` updates.
