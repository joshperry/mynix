{ pkgs, ... }:
# Disk and array health: smartd with scheduled self-tests, a monthly md
# consistency check and a monthly btrfs scrub. A problem raises the alarm
# (beep.nix): a flag file in /run/kago-alarm, beeped every 5 minutes until it
# is removed or kago reboots (smartd re-flags a persisting problem at start).
#
# Monthly schedule, spread so no two full-disk reads overlap (a long self-test
# of a 14T Exos is ~20h, the md check about the same):
#   first Sunday  md check of md0 (data)
#   10th/12th/14th  SMART long self-test of one disk each
#   20th          btrfs scrub of the data volume
let
  disks = {
    ZHZ680TR = "10";
    ZHZ63P8S = "12";
    ZHZ5JXXZ = "14";
  };

  smartdNotify = pkgs.writeShellScript "kago-smartd-notify" ''
    mkdir -p /run/kago-alarm
    printf '%s\n%s\n' "$SMARTD_DEVICESTRING" "$SMARTD_FULLMESSAGE" \
      > "/run/kago-alarm/smart-''${SMARTD_DEVICE##*/}"
    ${pkgs.util-linux}/bin/logger -p daemon.crit -t smartd-alarm \
      "$SMARTD_DEVICESTRING: $SMARTD_MESSAGE"
  '';
in
{
  services.smartd = {
    enable = true;
    # Only the listed disks; no wall (nobody is logged in to see it).
    autodetect = false;
    notifications.wall.enable = false;
    # -a: health, attributes, error/self-test logs; -o/-S: offline data
    # collection and attribute autosave. Short self-test daily at 02:00.
    devices = map (serial: {
      device = "/dev/disk/by-id/ata-ST14000NM0018-2H4101_${serial}";
      options = "-a -o on -S on -s (S/../.././02|L/../${disks.${serial}}/./04) "
        + "-m <nomailer> -M exec ${smartdNotify}";
    }) (builtins.attrNames disks);
  };

  # nixpkgs' mdadm ships mdcheck_start.timer, but not the mdcheck script it
  # runs. The check itself runs in the kernel at idle I/O priority
  # (speed_limit_min); this waits for it and raises the alarm on mismatches.
  systemd.services.kago-md-check = {
    description = "Consistency check of the md data array";
    onFailure = [ "kago-alarm@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";
    };
    script = ''
      md=/sys/block/$(basename "$(readlink -f /dev/md/data)")/md
      action=$(cat $md/sync_action)
      if [ "$action" != idle ]; then
        echo "md data array busy ($action), skipping"
        exit 0
      fi
      echo check > $md/sync_action
      sleep 60
      while [ "$(cat $md/sync_action)" != idle ]; do sleep 300; done
      mismatches=$(cat $md/mismatch_cnt)
      echo "check finished, mismatch_cnt=$mismatches"
      [ "$mismatches" = 0 ]
    '';
  };
  systemd.timers.kago-md-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-1..7 01:00";
      Persistent = true;
    };
  };

  # Exits 3 on uncorrectable errors: with btrfs data single on md, any
  # checksum error is uncorrectable.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/mnt/md0" ];
    interval = "*-*-20 02:00";
  };
  systemd.services.btrfs-scrub-mnt-md0.onFailure = [ "kago-alarm@%n.service" ];
}
