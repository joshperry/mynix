#!/usr/bin/env bash
set -e

function verify_me() {
  read -p "$1 " choice
  case "${choice,,}" in 
    y|yes ) echo "yes";;
    * ) echo "no";;
  esac
}

nixos-rebuild build --flake . --show-trace
command -v nvd >/dev/null 2>&1 \
  && nvd diff /run/current-system result

if [[ "yes" == $(verify_me "Switch?") ]]; then
  sudo nix-env -p /nix/var/nix/profiles/system --set ./result
  sudo result/bin/switch-to-configuration switch
  unlink result
fi
