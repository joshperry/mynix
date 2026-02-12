# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

"mYniX" is a personal NixOS flake configuration managing multiple machines with a custom module and package hierarchy. It uses NixOS + home-manager + flakes to declaratively configure entire Linux systems per-machine.

## Development Commands

The repository uses `nix-direnv` integration (`.envrc`). When entering the directory, a devShell provides these commands:

- **`buildsys`**: Build the current host's NixOS configuration, show diff with `nvd`, and optionally apply it
- **`updatesys`**: Update `flake.lock` (runs `nix flake update`)
- **`flash-installer <hostname> <device>`**: Build a minimal installer ISO with prebuilt system and write to USB device

Standard NixOS commands also work:
- `nixos-rebuild build --flake .`: Build without switching
- `nixos-rebuild build --flake .#<hostname>`: Build specific machine configuration
- `nix flake update`: Update all flake inputs
- `nix flake lock --update-input <input>`: Update specific input

## Architecture

### Flake Structure

The flake exports configurations via `nixosConfigurations.<hostname>` using a custom `nixosSystem` helper function (flake.nix:56). This helper simplifies the standard `lib.nixosSystem` by:

1. Automatically importing `machines/${name}/configuration.nix` and `hardware-configuration.nix`
2. Integrating home-manager for user environments from `users/${username}/`
3. Mounting `nixpkgs-unstable` at `pkgs.unstable` via overlay
4. Merging custom packages from `./packages/` into `pkgs.mynix`
5. Supporting optional `sysmodules` parameter for additional NixOS modules

### Machine Configurations

Each machine lives in `machines/<hostname>/`:
- `configuration.nix`: Machine-specific NixOS configuration
- `hardware-configuration.nix`: Hardware-specific settings (usually auto-generated)
- Optional `disks.nix`: Disko disk partitioning configuration (used by installer)

Machines import profile modules from `profiles/`:
- `common.nix`: Base configuration for all machines (enabled flakes, common packages)
- `graphical.nix`: Desktop/GUI configuration (imports common.nix)
- `server.nix`: Server configuration (imports common.nix)

### User Configurations

User home-manager configurations live in `users/<username>/`:
- `default.nix`: Primary user configuration (graphical systems)
- `server.nix`: Server-specific user configuration (minimal, CLI-only)
- `cli.nix`: Shared CLI configuration imported by default.nix
- `machines/<hostname>/`: Machine-specific user overrides

The flake's `nixosSystem` helper passes the user configuration to `home-manager.users.<username>`.

### Modules

Custom NixOS modules are in `modules/`:
- `default.nix`: Imports all modules as a list
- `security/`: Security-related modules (drata, falcon-sensor, fprintd-lidcheck)

These are automatically imported by the `nixosSystem` helper (flake.nix:63).

### Packages

Custom packages are defined in `packages/default.nix` and merged into `pkgs.mynix`:
- `mynix.drata`, `mynix.ansel`, `mynix.HELI-X`, etc.: Custom or patched applications
- `mynix.dev.direnv-nvim`: Development tools
- `mynix.NvidiaOffloadApp`: Utility function to patch desktop entries for NVIDIA Optimus
- `mynix.xss-lock-hinted`, `mynix.i3lock-color`: Overridden packages with patches

The flake also provides `pkgs.unstable` for nixpkgs-unstable packages (flake.nix:68).

### Overlays

Package overlays are applied in this order (flake.nix:30-46):
1. nix-snapshotter overlay (OCI/container tools)
2. litnix overlay (literate nix tooling)
3. Private packages from `./packages/` (merged as `pkgs.mynix`)
4. Unstable nixpkgs at `pkgs.unstable` (flake.nix:68)

### Current Machines

- **signi**: Primary graphical workstation (impermanence, nix-snapshotter, two users: josh + ada)
- **bones**: Graphical workstation
- **mantissa**: Graphical workstation
- **xeeps**: Graphical workstation with solo.nix config
- **liver**: Server (minimal user config from users/josh/server.nix)
- **mino**: Server with disko and impermanence
- **sandboxos**: Test/sandbox environment

## Key Conventions

- Machine configurations use `profiles/graphical.nix` or `profiles/server.nix` which import `profiles/common.nix`
- Unfree packages are explicitly allowlisted per-machine via `nixpkgs.config.allowUnfreePredicate`
- The nix registry includes `nixpkgs` and `nixpkgs-unstable` pointing to the flake's locked versions
- Home-manager uses `useGlobalPkgs = true` and `useUserPackages = true`
- System state version and home.stateVersion track NixOS releases (e.g., "24.11", "23.11")

## Flake Inputs

- `nixpkgs`: NixOS 25.11 stable
- `nixpkgs-unstable`: NixOS unstable channel
- `home-manager`: Release 25.11 (follows nixpkgs)
- `disko`: Declarative disk partitioning
- `impermanence`: Ephemeral root filesystem support
- `nix-snapshotter`: OCI container integration for Nix (local path)
- `litnix`: Literate nix tooling (local path)
- `flake-parts`: Flake organization framework

## Installer System

Each machine configuration includes a `.installer` attribute that builds a minimal NixOS ISO with:
- Pre-built target system closure embedded
- `install-system` script that runs `disko-install --flake .#<hostname>`
- SSH access enabled for remote installation
- Use `flash-installer <hostname> <device>` to write to USB

## Testing Changes

1. Make changes to configuration files
2. Run `buildsys` to build, review diff, and optionally switch
3. Check `nvd` output for package/service changes before applying
4. For new machines, test build with: `nixos-rebuild build --flake .#<hostname>`

## Claude Code Workflow

When Claude Code runs as user `ada`, it runs in non-interactive bash sessions so cannot use the interactive `buildsys` command. Instead, use these steps to build and switch system configurations:

1. **Build the system**:
   ```bash
   nixos-rebuild build --flake . --show-trace
   ```

2. **Review changes**:
   ```bash
   nvd diff /run/current-system result
   ```

3. **Switch to new configuration** (requires approval):
   ```bash
   sudo sh -c 'nix-env -p /nix/var/nix/profiles/system --set ./result && ./result/bin/switch-to-configuration switch'
   ```
   This triggers the approval system once - josh gets a GUI popup to approve/deny.

4. **Cleanup**:
   ```bash
   unlink result
   ```

This workflow mirrors what `buildsys` does, but works in non-interactive sessions with explicit approval required for privileged operations.

## Active Work

### sops-age-yubikey boot decryption

Module: `modules/security/sops-age-yubikey.nix`, configured in `machines/signi/configuration.nix:225-229`.

**Previous fixes** (already in place):
- Systemd deps changed from `pcscd.service` to `pcscd.socket`
- `--card-status` retries in a loop (30 attempts, 1s sleep) instead of silent `|| true`
- gpg-agent.conf written before key import
- Clearer tty1 prompts

**Bug 1 (fixed)**: `$(which pinentry-curses)` resolved to empty string — `which` not in
service PATH. gpg-agent got empty `pinentry-program`, died exit 2, killed script via `set -e`.
Fix: nix interpolation `${pkgs.pinentry-curses}/bin/pinentry-curses`.

**Bug 2 (fixed)**: Pinentry prompt appeared on tty1 but display-manager started X
immediately, covering it before user could interact. Fix: added `display-manager.service`
to the unit's `before` list so X waits for decryption to complete.

**Status**: Both fixes switched, needs reboot to verify. On reboot tty1 should show
pinentry prompt with no X covering it. Touch YubiKey when prompted.
If it fails, check `sudo journalctl -b -u sops-age-yubikey.service`.
