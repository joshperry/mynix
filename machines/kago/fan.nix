{ pkgs, ... }:
# HDD-temperature fan control for the F5-221's single fan (IT8613E FAN3/PWM3).
#
# Port of TOS syscontrol's jf3355 curve (readme: Fan), on the out-of-tree
# it87 driver and drivetemp instead of raw port I/O and smartctl:
#   T = hottest drive; T <= 35 -> floor, 36..50 -> 100 + 10*(T-35), > 50 -> 255
# Changes from TOS: a 80/255 (~600 rpm) floor instead of stopping the fan,
# 30s interval instead of 300s, full speed if no drive temps can be read or
# the service stops, and poweroff after two consecutive readings >= 70C.
{
  systemd.services.kago-fan = {
    description = "HDD temperature fan control (IT8613E pwm3)";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils pkgs.gnugrep pkgs.systemd ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 10;
    };
    script = ''
      hw=$(dirname "$(grep -lx it8613 /sys/class/hwmon/hwmon*/name | head -1)")
      [ -e "$hw/pwm3" ] || { echo "it8613 hwmon not found"; exit 1; }

      full() { echo 255 > "$hw/pwm3"; }
      trap full EXIT
      echo 1 > "$hw/pwm3_enable"  # manual

      hot=0
      while true; do
        t=0
        for d in $(grep -lx drivetemp /sys/class/hwmon/hwmon*/name); do
          v=$(cat "$(dirname "$d")/temp1_input" 2>/dev/null) || continue
          [ $((v / 1000)) -gt $t ] && t=$((v / 1000))
        done

        if [ $t -eq 0 ]; then
          duty=255
          echo "no drive temperatures, fan full"
        elif [ $t -le 35 ]; then
          duty=80
        elif [ $t -gt 50 ]; then
          duty=255
        else
          duty=$((100 + 10 * (t - 35)))
        fi
        echo $duty > "$hw/pwm3"

        if [ $t -ge 70 ]; then
          hot=$((hot + 1))
          echo "drives at ''${t}C ($hot)"
          [ $hot -ge 2 ] && systemctl poweroff
        else
          hot=0
        fi
        sleep 30
      done
    '';
  };
}
