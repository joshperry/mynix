#!/usr/bin/env bash
set -e

function verify_me() {
  read -p "$1 " choice
  case "${choice,,}" in 
    y|yes ) echo "yes";;
    * ) echo "no";;
  esac
}

nixos-rebuild build --flake .
nvd diff /run/current-system result

if [[ "yes" == $(verify_me "Switch?") ]]; then
  sudo nix-env -p /nix/var/nix/profiles/system --set ./result
  sudo result/bin/switch-to-configuration switch
  unlink result
fi
