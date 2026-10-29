#!/bin/bash
# Clean TOS -> NixOS-in-RAM handover for kago. Run as root, detached:
#   setsid nohup bash handover.sh /home/ada/kexec >/dev/null 2>&1 &
# Any failure before kexec falls back to a normal reboot into TOS.
set -u
# sudo's secure_path on TOS lacks /sbin and /usr/sbin (swapoff, reboot, start-stop-daemon, rpc.nfsd).
export PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin
KDIR=$1
LOG=/root/kexec-handover.log   # on md9 (TOS root), readable after a fallback boot
exec >>"$LOG" 2>&1
echo "=== handover $(date)"
cd /

fail() { echo "FAILED: $*; rebooting into TOS"; sync; reboot; exit 1; }

# 1. Load kernel + initrd (upstream run script minus its unclean background kexec -e).
sed '/^# Disconnect our background kexec/,$d' "$KDIR/run" > "$KDIR/run-load"
SUDO_USER=ada sh "$KDIR/run-load" || fail "kexec load"
[ "$(cat /sys/kernel/kexec_loaded)" = 1 ] || fail "kexec_loaded != 1"
cp "$KDIR/kexec" /tmp/kexec-bin || fail "copy kexec binary"
echo "kexec image loaded"

# 2. Stop TOS services that touch the data volume.
pkill -f syscontrol   # fan stays at its last duty (0xe6) until it87 takes over
for s in snapshot samba nfs plex transmission docker rsync_service ftp blackblaze \
         redis minidlnad upnpd php-fpm nginx tosdeamon cron; do
    [ -x /etc/init.d/$s ] && /etc/init.d/$s stop
done
pkill -f rsswatcher; pkill -f msgcenter; pkill -f regcloud; pkill -f nasips; pkill -f TOSDeamon
pkill -f "mdadm --monitor"; pkill crond
sleep 3

# 3. Kill stragglers on md0 (incl. ssh sessions with cwd under /home), swap off, unmount.
for m in /mnt/md0/appdata/docker/btrfs /nix /home /mnt/md0; do
    fuser -km "$m" 2>/dev/null
done
sleep 2
swapoff -a || fail "swapoff"
for m in /mnt/md0/appdata/docker/btrfs /nix /home /mnt/md0; do
    if grep -q " $m " /proc/mounts; then umount "$m" || fail "umount $m"; fi
done
grep -q vg0-lv0 /proc/mounts && fail "data volume still mounted"
echo "data volume unmounted"

# 4. Quiesce: TOS root read-only, let md mark arrays clean, kexec.
sync
echo "kexec -e at $(date)"; sync
mount -o remount,ro / || echo "warning: / remount ro failed"
sleep 3
/tmp/kexec-bin -e
fail "kexec -e returned"
