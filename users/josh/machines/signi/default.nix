{ pkgs, ... }:
{
  imports = [ ../.. ];

  home.file.".screenlayout/screen-laptop.sh" = {
    executable = true;
    text = "xrandr --output DP-0 --off --output DP-1 --off --output eDP-1 --primary --mode 1920x1200 --pos 0x0 --rotate normal --output DP-1-0 --off --output DP-1-1 --off --output DP-1-2 --off --output HDMI-1-1 --off --output DP-1-3 --off";
  };

  home.file.".screenlayout/screen-home.sh" = {
    executable = true;
    # dell ultrawide, Displayport, right USB-C (not nvidia)
    text = "xrandr --output DP-1-0 --primary --mode 3840x1600 --pos 0x0 --rotate normal --output DP-0 --off --output DP-1 --off --output eDP-1 --off --output DP-1-1 --off --output DP-1-2 --off --output HDMI-1-1 --off --output DP-1-3 --off";
  };

  # nix-snapshotter / k3s-rootless removed 2026-02-12
  # Was: containerd rootless + nix-snapshotter rootless + k3s rootless (nix snapshotter)
  # The k3s patch in /home/josh/dev/nix-snapshotter/modules/flake/overlays.nix
  # broke against nixpkgs k3s 1.34.3+k3s3 (go.sum hunk #3 fails to apply).
  # Plan: rebuild nix-snapshotter as a standalone flake, rebase the k3s patch,
  # and re-integrate once it's stable independent of the system flake.
}
