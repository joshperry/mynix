{ pkgs, ... }:
let
  k3senv = pkgs.writeTextFile {
    name = "k3s.env";
    text = "";
  };
in
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

  # Nix-snapshotter shenanigans
  virtualisation.containerd.rootless = {
    enable = true;
    nixSnapshotterIntegration = true;
  };

  services.nix-snapshotter.rootless = {
    enable = true;
  };

  services.k3s.rootless = {
    enable = true;
    snapshotter = "nix";
    environmentFile = "${k3senv}";
  };
}
