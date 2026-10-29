{ pkgs, ... }:
# Ready/shutdown beeps, as TOS did. TOS's /usr/bin/buzzer drove the PC
# speaker by hand (PIT channel 2 via ports 0x43/0x42, gate bits on 0x61);
# `buzzer all` with its defaults is one 350ms beep at divisor 600 (~1989Hz).
# Same sound through the stock pcspkr driver and beep(1).
let
  tosBeep = "${pkgs.beep}/bin/beep -f 1989 -l 350";
  # Alarm: three short high beeps.
  alarmBeep = "${pkgs.beep}/bin/beep -f 2983 -l 150 -r 3 -d 100";
in
{
  boot.kernelModules = [ "pcspkr" ];

  # Boot reached multi-user.target: normal services are up (plex may still be
  # starting, as on TOS).
  systemd.services.kago-beep-ready = {
    description = "Beep when kago is up";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = tosBeep;
    };
  };

  # Alarm: nag every 5 minutes while any md array is missing a member
  # ([UU_], TOS buzzer_config raid_drive_miss), including during a rebuild, or
  # while anything has left a flag in /run/kago-alarm (health.nix). Clear a
  # flag with `sudo rm /run/kago-alarm/<name>` once dealt with.
  systemd.services.kago-raid-alarm = {
    description = "Beep while an md array is degraded or an alarm is raised";
    path = [ pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    script = ''
      alarm=
      if grep -qE '\[U*_[U_]*\]' /proc/mdstat; then
        echo "md array degraded:"; grep -B1 -E '\[U*_[U_]*\]' /proc/mdstat
        alarm=1
      fi
      for f in /run/kago-alarm/*; do
        [ -e "$f" ] || continue
        echo "alarm raised: $f"; cat "$f"
        alarm=1
      done
      if [ -n "$alarm" ]; then ${alarmBeep}; fi
    '';
  };
  # OnFailure= target for health checks: raise the alarm for unit %i.
  systemd.services."kago-alarm@" = {
    description = "Raise the alarm for %i";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /run/kago-alarm
      echo "$1 failed, see: journalctl -u $1" > "/run/kago-alarm/$1"
    '';
    scriptArgs = "%i";
  };
  systemd.timers.kago-raid-alarm = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };

  # Ordered before basic.target, so on shutdown it is stopped after every
  # normal service, right before filesystems unmount and power-off.
  systemd.services.kago-beep-shutdown = {
    description = "Beep when kago is about to power off";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" "systemd-modules-load.service" ];
    before = [ "basic.target" "shutdown.target" ];
    conflicts = [ "shutdown.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = tosBeep;
    };
  };
}
