# kago

TerraMaster F5-221 NAS, being migrated from TOS 4.2.44 to NixOS **in place**:
the TOS data volume (md RAID5 → LVM → btrfs) is kept as-is.

Status (2026-10-28): **running NixOS**, installed in place over TOS; data
volume kept. See "Install log" below. ada has TEMP full sudo in
`configuration.nix` until things settle.

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

The BIOS (custom TerraMaster AMI, boot priority list locked/greyed out) boots
the **disks**: TOS's GRUB 2 (i386-pc) in each disk's MBR, config on `sdX1`
(`boot/grub/grub.cfg`). The internal USB flash carries the same GRUB and config
(`boot/grub2/grub.cfg`) and is #4 in the order; Boot Override (Save & Exit)
can pick it for one boot. Both TOS configs do:

```
insmod mdraid1x
if [ -e (md/UTOSCORE-X86-S64)/boot/bzImage ]; then   # md9
    set root=(md/UTOSCORE-X86-S64); linux /boot/bzImage type=raid
else                                                # fresh NAS: installer
    set root=(hd0,gpt1);            linux /boot/bzImage type=usb
fi
```

No initrd and a fixed command line, so it can't boot NixOS directly. NixOS
manages only its own config on `md9` (`boot.loader.grub.devices = [ "nodev" ]`)
and `boot.loader.grub.extraInstallCommands` writes `usbflash-grub.cfg` over all
four TOS configs (disks matched by serial, flash by label), keeping each TOS
original as `grub.cfg.tos`. That config `configfile`s
`(md/UTOSCORE-X86-S64)/grub/grub.cfg`, with the TOS INIT system as a manual
second entry. Nothing is installed to any MBR and the BIOS is untouched.

When `md9` holds no TOS kernel the stock configs boot the INIT system
(`type=usb`): a web "Initialization" wizard on :80 that **wipes the disks** if
clicked through, with a fresh ssh host key on 9222. That's what happened on the
first reboot (only the flash had been edited, on the wrong assumption it was
the boot device). TOS hides the flash after boot (`/etc/init.d/mountusb stop`
deletes the SCSI device); under NixOS it is `sdd`.

The flash and disk GRUBs are TOS-era (pre-2.12): `/boot` must be ext4 without
`metadata_csum`, `metadata_csum_seed` or `orphan_file` (TOS's own md9 feature
set), and `splashImage = null`.

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
the disk temps, and `fan.nix` runs the same curve with a 600 rpm floor.

## LEDs (investigated, nothing to port)

The bay LEDs are dim green with a drive present and brighter on activity, empty
bays off — all driven by hardware (SATA presence/activity), no software needed.
Reviews and TerraMaster's FAQ describe the bays as red at power-on, green when
ready, and red for a failed drive; this unit has not been seen red, and it is
not known whether its LEDs are bi-colour (check next time the case is open).

TOS's two LED paths are generic J3355-family code and do nothing visible here:

- `led_drv_TMJ33.ko` (`/dev/leddrvN`, commands `led1on`…`led10off`): bit 0
  (GPIOTXState) of SoC North-community pads 23–32 (P2SB port 0xC5, PADCFG
  0x5B8–0x600; P2SB BAR read from PCI 0:0d.0). Linux: `gpiochip0` lines 23–32,
  all outputs. Flipped each both ways: no change.
- `syscontrol` (`driv_set_led`, used on this board since `leddevice == 1`):
  IT8613E simple-I/O data ports, LED1/3/5/7/9 active-low on `a05`.3, `a02`.1,
  `a02`.2, `a02`.3, `a03`.1; LED2/4/6/8/10 active-high on `a01`.3, `a01`.1,
  `a03`.3, `a03`.4, `a03`.5 (simple I/O base 0x0a00, so `a01` = set 2). The
  pins are GPIO + simple I/O + output-enabled (LDN 7 0xC1–0xC3 / 0xC9–0xCB).
  Each bit flipped alone, and odd/even combined across all bays: no change.
  LED11/12 (eth0/eth1 carrier) are no-ops on this board. TOS's `sys_ledN`
  threads blinked LED1–5 in software from diskstats.

Nothing else in TOS touches LEDs: the kernel has only stock AHCI
enclosure-management (`em_message`, unused; the ASM1061s advertise `led`), and
the INIT initramfs's `aplcontrol` is an older `syscontrol` build.

Failure signalling is audible instead (`beep.nix`, TOS buzzer_config parity):
RAID degraded → three high beeps every 5 minutes; drives ≥70°C → five beeps
per fan-loop reading before the poweroff.

## Services (TOS → NixOS)

| TOS | NixOS | Notes |
|---|---|---|
| Samba `public` `appdata` `media` `bu` (recycle on media/bu) | `services.samba` | `appdata_bak` and `[homes]` dropped |
| Plex (native, `/home/plex/Library/Application Support`) | `services.plex` with that `dataDir` | Media paths in the DB stay valid since `/mnt/md0` is kept |
| Transmission (watch `/mnt/md0/public/rssseeds`) | `services.transmission` | TOS `rsswatcher` not ported |
| btrfs snapshots (cron → `snapshot_schedule_task.php`) | `services.btrbk` (`backup.nix`) | TOS kept `bu` dailies (7) and `media`/`public` hourlies (5 each); `appdata` every 5 min (deleted). btrbk does `bu` daily so far |
| Backblaze rclone sync `bu/offsite` → bucket `kago-bu` (held one test file) | `services.restic` → `b2:kago-bu:restic` (`backup.nix`) | Daily from a read-only snapshot at a fixed path; 7d/5w/12m. B2 creds in `secrets/kago.yaml` are **placeholders** until filled in |
| sshd 9222/9223 | sshd 22 | add `kago.local` (port 22) to ada's pinned known_hosts at cutover; same host key |
| `buzzer all` at boot end / shutdown (PC speaker by hand: PIT ch2 `0x43`/`0x42`, gate `0x61`; one 350ms beep, divisor 600 ≈ 1989Hz) | `beep.nix` (pcspkr + beep(1)) | ready beep after multi-user.target; shutdown beep after services stop |
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

## Install log (2026-10-28)

Rollback material lives in btrfs subvolume `@kago-migration` on the data
volume (root-only): `usbflash.img` (whole flash, pre-edit), `md9-tos-root.img`
(TOS root, byte-verified), `tos-etc/` (ssh host keys, smbpasswd, passwd/group,
smb.conf, transmission settings), `idscan/` (pre-remap uid/gid/ACL histograms),
`remap.log`. Restoring TOS = write `md9-tos-root.img` back to md9 and the
`grub.cfg.tos` files back over `grub.cfg` (or the flash image).

1. From TOS: saved `tos-etc/`; scanned ids (~1.12M files across media, bu,
   public, appdata, User).
2. Handover to the kexec environment (`kexec/`). Assembled arrays by UUID
   (they come up as md125-127 there, no `/dev/md/<name>` links without udev
   rules); imaged flash and md9, `cmp`-verified.
3. `mdadm --grow --raid-devices=3` on md9 and md8 (72 slots → 3).
4. `mkfs.ext4 -L KAGOBOOT -O ^metadata_csum,^metadata_csum_seed,^orphan_file`
   on md9; `mkswap` on md8.
5. Deleted `@nix` (TOS-side tooling store); created `@nixos/{root,nix}`.
6. Ownership: `remap-ids.awk` (getfacl → awk → `setfacl -P --restore`, plus
   `chown -h` for symlinks). Dry run on a reflink copy first; afterwards zero
   files or ACL entries with TOS ids.
7. Closure: kago fetched the 916 cache.nixos.org paths itself (`nix copy
   --from https://cache.nixos.org --to /mnt`); the 149 local-only paths
   (config, it87, unfree plex, ...) were piped from signi with
   `nix-store --export | nix-store --store /mnt --import`. A single
   export/import of the whole 5.5G closure OOM-kills in the 1.8G RAM
   environment; enable swap on md8 first.
8. TOS ssh host keys into `/mnt/etc/ssh` (sops derives kago's age key from
   the ed25519 one), then `nixos-install --system ... --no-root-passwd`.
9. Edited the flash `grub.cfg` and rebooted — into the TOS INIT wizard, since
   the BIOS boots the disks (see Boot). Recovered with a monitor: Boot
   Override → USB flash; kago reached over a direct cable to signi
   (NetworkManager `ipv4.method shared` connection `kago-direct`, 10.42.0.0/24,
   ssh with `-o HostKeyAlias=kago.local`).
10. From NixOS: the grub hook rewrote all four TOS configs; plex `dataDir`
    moved to `/mnt/md0/User/plex/...` (the unit's `ProtectHome` hides /home);
    md9 had assembled with only `sda2` (`sdb2`/`sdc2` went stale during the
    INIT boot) — zeroed and re-added; Samba passwords imported from TOS's
    smbpasswd with uids remapped (`pdbedit -i smbpasswd:... -e tdbsam`).

Deploying: build on signi, `nix copy --no-check-sigs --to ssh-ng://ada@kago.local`
(ada is a trusted user, but the ssh-ng `nix-daemon --stdio` proxy still checks
signatures without the flag), then `sudo nix-env -p /nix/var/nix/profiles/system
--set <path>` and `sudo <path>/bin/switch-to-configuration switch`.

Still to do: drop ada's TEMP full sudo; clean up TOS leftovers on the data
volume: `@snapshot/{bu,media,public}` (TOS snapshots, kept until btrbk has its own history) and `@kago-migration` (rollback). Deleted 2026-10-29: `appdata_bak`, `@system`, `@zlog`, `application`, `@snapshot/appdata`.
