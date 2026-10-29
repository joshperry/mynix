{ config, pkgs, ... }:
# Local btrfs snapshots of bu, and an offsite restic backup of bu/offsite to
# Backblaze B2 (replaces TOS's rclone "cloudsync" of the same directory into
# bucket kago-bu, which only ever held a test file).
let
  snap = "/mnt/md0/@snapshot/restic/bu";
in
{
  sops = {
    defaultSopsFile = ../../secrets/kago.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.restic-password = { };
    # B2_ACCOUNT_ID / B2_ACCOUNT_KEY lines, for restic's b2 backend.
    secrets.restic-b2-env = { };
  };

  # btrbk does not create its snapshot_dir.
  systemd.tmpfiles.rules = [ "d /mnt/md0/@snapshot/btrbk 0755 root root -" ];

  # TOS kept 7 dailies of bu.
  services.btrbk.instances.bu = {
    onCalendar = "daily";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "7d";
      volume."/mnt/md0" = {
        snapshot_dir = "@snapshot/btrbk";
        subvolume.bu = { };
      };
    };
  };

  # restic reads a read-only snapshot taken for the run, so the backup is
  # consistent without stopping anything. The snapshot always lives at the same
  # path, and btrfs snapshots keep inode numbers, so restic's change detection
  # (path/size/mtime/ctime/inode) skips unchanged files between runs.
  services.restic.backups.bu-offsite = {
    repository = "b2:kago-bu:restic";
    initialize = true;
    passwordFile = config.sops.secrets.restic-password.path;
    environmentFile = config.sops.secrets.restic-b2-env.path;
    paths = [ "${snap}/offsite" ];
    backupPrepareCommand = ''
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${snap})"
      if [ -e ${snap} ]; then ${pkgs.btrfs-progs}/bin/btrfs subvolume delete ${snap}; fi
      ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /mnt/md0/bu ${snap}
    '';
    backupCleanupCommand = ''
      ${pkgs.btrfs-progs}/bin/btrfs subvolume delete ${snap}
    '';
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];
    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
