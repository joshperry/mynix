# kago

TerraMaster F5-221 NAS, being migrated from TOS 4.2.44 to NixOS **in place**:
the TOS data volume (md RAID5 → LVM → btrfs) is kept as-is.

Status (2026-10-28): audit done, NixOS-from-RAM test passed (step 1), config
written and building. **Not installed yet** — kago is still on TOS.

## Hardware

| | |
|---|---|
| Board | `TM-J3355-2G2L` (GIFA), AMI BIOS `MAPL0304V17`, legacy boot (no UEFI in use) |
| CPU / RAM | Celeron J3355 (Apollo Lake, 2C), 1.8G usable — build on signi, copy over |
| SATA | SoC AHCI (2 ports) + 2× ASM1061 (2 ports each); 3 of 5 bays used |
| Disks | 3× Seagate ST14000NM0018 14T, same batch (37,112 power-on h on 2026-10-28), SMART clean |
| NIC | `eth1`/`enp0s21f0u5` = **USB** RTL8153 (`r8152`) is the one in use; onboard RTL8168 (`r8169`, `enp2s0`) is unused |
| Super I/O | ITE **IT8613E**: HWM at `0xa40`, GPIO (disk LEDs) at `0xa00` |
| Boot flash | internal USB `13fe:4100` "USB DISK 2.0", 120M, ext4 label `UTOSBOOT-X86-S64` |

## Disks

Each disk (GPT, all partitions type 8300; LBA 34–2047 free):

| Part | Size | Use | md | NixOS |
|---|---|---|---|---|
| `sdX1` | 285M | ext4, TOS installer copy of GRUB + kernel | — | unused |
| `sdX2` | 1.9G | RAID1, TOS root | `md9` `TNAS:UTOSCORE-X86-S64` `5ff70b39:a7fe55ae:7e85c47c:8171395a` | `/boot` (ext4, label `KAGOBOOT`) |
| `sdX3` | 977M | RAID1, swap | `md8` `kago:UTOSSWAP-X86-S64` `10dc9e34:7d622e82:7b5607ab:50480a3d` | swap |
| `sdX4` | 12.7T | RAID5 data | `md0` `kago:UTOSUSER-X86-S64` `8df3eb1b:8d413aad:bdc89b4f:8b7974fa` | kept |

`md8`/`md9` were created with **72** RAID1 slots (`[72/3]`), so mdadm sees them
as degraded until shrunk to 3 (install step).

Data stack, all standard and verified under NixOS 7.2.9 (step 1):
`md0` (metadata 1.2, 128k chunk, internal bitmap) → LVM2 `vg0/lv0` (plain
text metadata, written by lvm2 2.02.173; TOS just doesn't ship the tools) →
btrfs `3f27ef6a-38f2-4141-a5e6-080ed7e8a5e9` (crc32c, `free_space_tree`,
`skinny_metadata`, mainline features only, 0 device errors). TOS loads
`flashcache` but no cache devices exist.

btrfs subvolumes (top level mounted at `/mnt/md0`, as on TOS):
`media`, `bu`, `public`, `appdata` (Docker leftovers, ~2M), `appdata_bak`,
`User` (→ `/home`), `@system` (TOS thumbnails/redis), `@zlog`, `application`,
`@snapshot/…` (TOS snapshots), `@nix` (single-user Nix ada installed on TOS
for tooling; delete at install). NixOS adds `@nixos/root` and `@nixos/nix`.

## Boot

BIOS → internal USB flash → its GRUB 2 (i386-pc), whose `grub.cfg` does:

```
insmod mdraid1x
if [ -e (md/UTOSCORE-X86-S64)/boot/bzImage ]; then   # md9
    set root=(md/UTOSCORE-X86-S64); linux /boot/bzImage type=raid
else                                                # fresh NAS: installer
    set root=(hd0,gpt1);            linux /boot/bzImage type=usb
fi
```

No initrd and a fixed command line, so it can't boot NixOS directly. The
flash's `grub.cfg` gets edited to hand over to the NixOS-generated config on
`md9` (`boot.loader.grub.devices = [ "nodev" ]`): nothing is ever installed to
the disks' MBRs, the BIOS is untouched, and restoring the flash image brings
back TOS's boot/recovery path. TOS hides the flash after boot
(`/etc/init.d/mountusb stop` deletes the SCSI device); under NixOS it shows up
as `sdd`. The `sdX1` copies have the same `grub.cfg` but an older kernel; the
`(hd0,gpt1)` + `type=usb` branch implies the flash is first in the BIOS order.

## Fan

One fan, on IT8613E **FAN3/PWM3**. Registers (index `0xa45`, data `0xa46`):

| Reg | Meaning |
|---|---|
| `0x0f` / `0x1a` | FAN3 tach low/high; RPM = 1350000 / (2 × count) |
| `0x73` | PWM3 duty, 0–255 |
| `0x17` bit 7 | PWM3 automatic (SmartGuardian) mode; keyed to TMPIN1 (the chip's ~36°C sensor), **not** the disks — measured ~1000 rpm with disks at 48°C, so unusable |
| `0x29` / `0x2a` | TMPIN1 / TMPIN2 (TOS "cpu" / "sys" temp) |

Measured: duty 255 → 2000 rpm, 230 → 1820, 192 → 1540, 128 → 1025, 80 → 600.

TOS's `/usr/sbin/syscontrol` (static, not stripped, with debug info;
`fanctl-Jfang-3455.c: jf3355_fan_ctl`) every 300s, if `Autofan=1` in
`/tmp/TOS_CONFIG/.default.sys`: T = hottest disk (`smartctl`); T ≤ 35 → duty
0 (fan off), 36–50 → 100 + 10·(T−35), > 50 → 254; T > 70 twice → `shutdown -h
now`. `jf3355_fan_ctl(0x30)` would select chip auto mode; the thread never
passes it.

NixOS: `it87` from `linuxPackages.it87` (frankcrawford, supports IT8613E;
mainline doesn't) loads without `ignore_resource_conflict`, `drivetemp` gives
the disk temps, and `fan.nix` runs the same curve with a 600 rpm floor. The
front-panel LEDs (`led_drv_TMJ33.ko`, GPIO at `0xa00`) are not ported.

## Services (TOS → NixOS)

| TOS | NixOS | Notes |
|---|---|---|
| Samba `public` `appdata` `media` `bu` (recycle on media/bu) | `services.samba` | `appdata_bak` and `[homes]` dropped |
| Plex (native, `/home/plex/Library/Application Support`) | `services.plex` with that `dataDir` | Media paths in the DB stay valid since `/mnt/md0` is kept |
| Transmission (watch `/mnt/md0/public/rssseeds`) | `services.transmission` | TOS `rsswatcher` not ported |
| btrfs snapshots (cron → `snapshot_schedule_task.php`) | `services.btrbk` (`backup.nix`) | Only `bu` dailies (7 kept) actually existed |
| Backblaze rclone sync `bu/offsite` → bucket `kago-bu` (held one test file) | `services.restic` → `b2:kago-bu:restic` (`backup.nix`) | Daily from a read-only snapshot at a fixed path; 7d/5w/12m. B2 creds in `secrets/kago.yaml` are **placeholders** until filled in |
| sshd 9222/9223 | sshd 22 | add `kago.local` (port 22) to ada's pinned known_hosts at cutover; same host key |
| TOS web UI | `services.cockpit` on `:9090` | status, logs, services; no metrics history (PCP) on 2G RAM |
| NFS `/mnt/md0/media` → `10.0.2.10`, rsync daemon `[bu]` (`/mnt/bu`, nonexistent), smbftpd, Docker (no containers), minidlna, upnpd, k3s | dropped | |

## Users and ownership

Data is owned by TOS numeric ids and carries POSIX ACLs (`group:3`,
`group:4`). gid 4 is `messagebus` on NixOS, so ids are remapped during
install:

| TOS | id | NixOS | id |
|---|---|---|---|
| josh | uid 2 | josh | 1000 |
| janus | uid 5 | janus | 1001 |
| ada | uid 7 | ada | 1100 |
| plex | uid/gid 5555 | plex | 193 |
| transmission | uid/gid 1006 | transmission | 70 |
| admin | gid 3 | nas | 2000 |
| allusers | gid 4 | nas | 2000 |

`setfacl --restore` also applies the `# owner:`/`# group:` lines, so one
pass rewrites owners, groups and ACL entries:

```
getfacl -R -n -p <dir> | sed -E \
  -e 's/^# owner: 2$/# owner: 1000/'   -e 's/^# group: (3|4)$/# group: 2000/' \
  -e 's/^((default:)?user):2:/\1:1000:/' -e 's/^((default:)?group):(3|4):/\1:2000:/' \
  … | setfacl --restore=-
```

Skip `@snapshot` (read-only) and dry-run on one directory first.

## Step 1: NixOS from RAM (done 2026-10-28)

`kexec/` holds the environment: `flake.nix` is nixos-images'
kexec-installer (pinned) plus `it87`, `drivetemp`, the storage tools, Realtek
NIC firmware, sshd on 22 + 9222 and Avahi as `kago.local`, with
`boot.swraid` forced off so nothing auto-assembles. kexec-installer carries
TOS's ssh host keys, authorized keys and network config across.
`handover.sh` (run detached as root from TOS) loads the kexec image, stops
TOS services, kills users of the data volume, swaps off, unmounts everything
on `md0`, remounts `/` read-only and kexecs; any failure before that falls
back to `reboot`. Log: `/root/kexec-handover.log` on TOS.

```
nix build ./machines/kago/kexec          # 480M tarball
# copy to kago:/home/ada/kexec (data volume), handover.sh to /tmp (tmpfs!)
sudo setsid nohup bash /tmp/handover.sh /home/ada/kexec </dev/null >/dev/null 2>&1 &
```

Results: `md0` assembled `--readonly` as **clean** (0 dirty bitmap pages), LVM
+ btrfs + all subvolumes mount, ACLs readable, `it87` drives PWM3 through
sysfs, pinned host key valid, ~950M RAM free. `reboot` returns to TOS.

Lessons: TOS's sudo `secure_path` lacks `/sbin` and `/usr/sbin`; `handover.sh`
must live on tmpfs (bash reads scripts lazily and the fuser step would kill
it); never chain `cat > file && … &` over ssh (the background job gets stdin
from `/dev/null` and empties the file); `fuser -km /home` also kills
interactive sessions.

## Install (steps 2–4, not done)

From the kexec environment, data volume read-write:

1. **Backups first:** offsite `bu` current; `dd` the boot flash (`sdd`) to
   `/mnt/md0/@kago-migration/usbflash.img`; copy TOS's `/etc/ssh/ssh_host_*`,
   `/etc/samba/smbp` (smbpasswd), `/etc/passwd`/`group` and
   `/usr/local/transmission/settings.json` next to it (do this from TOS, before
   handover).
2. Shrink the RAID1s: `mdadm --grow /dev/md9 --raid-devices=3`, same for
   `md8`.
3. `mkfs.ext4 -L KAGOBOOT /dev/md9`; `mkswap /dev/md8`.
4. `btrfs subvolume create /mnt/md0/@nixos{,/root,/nix}`; delete `@nix`.
5. Remap ownership (above).
6. On signi: build `.#nixosConfigurations.kago`, `nix copy` to the target
   store; `nixos-install --system <path> --no-bootloader --root /mnt`, then
   generate `/boot/grub/grub.cfg` (`switch-to-configuration boot` in the
   chroot).
7. Restore the TOS host keys into `/mnt/etc/ssh`; import Samba passwords:
   `pdbedit -i smbpasswd:smbp -e tdbsam:/var/lib/samba/private/passdb.tdb`.
8. Edit the flash's `boot/grub2/grub.cfg`: keep the `insmod mdraid1x` and
   the INIT fallback, replace the RAID branch with
   `configfile (md/UTOSCORE-X86-S64)/grub/grub.cfg`. Check first that the
   flash GRUB's modules can read what the NixOS `grub.cfg` uses (search by
   fs uuid, ext2).
9. Reboot. Rollback: write `usbflash.img` back; TOS's root on `md9` is gone
   by then, so TOS would come up as a fresh install from the flash (data
   volume untouched).
