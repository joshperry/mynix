{
  imports = [ ../.. ];

  home.file.".screenlayout/screen-laptop.sh" = {
    executable = true;
    text = "xrandr --output DP-0 --off --output DP-1 --off --output eDP-1-1 --primary --mode 1920x1200 --pos 0x0 --rotate normal --output DP-1-0 --off --output DP-1-1 --off --output DP-1-2 --off --output HDMI-1-1 --off --output DP-1-3 --off";
  };

  home.file.".screenlayout/screen-home.sh" = {
    executable = true;
    # dell ultrawide, Displayport, right USB-C (not nvidia)
    text = "xrandr --output DP-1-0 --primary --mode 3840x1600 --pos 0x0 --rotate normal --output DP-0 --off --output DP-1 --off --output eDP-1-1 --off --output DP-1-1 --off --output DP-1-2 --off --output HDMI-1-1 --off --output DP-1-3 --off";
  };
}
