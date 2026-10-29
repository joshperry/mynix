{ config, lib, modulesPath, ... }:
# TerraMaster F5-221 (board TM-J3355-2G2L, Celeron J3355, 2G RAM), legacy BIOS.
# Disk layout is TOS's, kept as-is; see readme.md for how it was mapped.
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "usb_storage" "sd_mod" "dm_mod" ];
  boot.kernelModules = [ "coretemp" "drivetemp" "it87" ];
  # IT8613E Super I/O (fan + LEDs) is not in mainline it87.
  boot.extraModulePackages = [ config.boot.kernelPackages.it87 ];

  # TOS mdraid sets, assembled by UUID. md9/md8 were created with 72 RAID1
  # slots; the install shrinks them to 3 (readme) so they aren't "degraded".
  #   sd[abc]2 -> boot (TOS "TNAS:UTOSCORE-X86-S64", the name the flash GRUB looks for)
  #   sd[abc]3 -> swap (TOS "kago:UTOSSWAP-X86-S64")
  #   sd[abc]4 -> data (TOS "kago:UTOSUSER-X86-S64", RAID5 -> LVM vg0/lv0 -> btrfs)
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      MAILADDR root
      ARRAY /dev/md/boot metadata=1.2 UUID=5ff70b39:a7fe55ae:7e85c47c:8171395a
      ARRAY /dev/md/swap metadata=1.2 UUID=10dc9e34:7d622e82:7b5607ab:50480a3d
      ARRAY /dev/md/data metadata=1.2 UUID=8df3eb1b:8d413aad:bdc89b4f:8b7974fa
    '';
  };

  fileSystems = let
    data = "/dev/disk/by-uuid/3f27ef6a-38f2-4141-a5e6-080ed7e8a5e9";  # btrfs on vg0/lv0
  in {
    "/" = {
      device = data;
      fsType = "btrfs";
      options = [ "subvol=@nixos/root" "noatime" ];
    };
    "/nix" = {
      device = data;
      fsType = "btrfs";
      options = [ "subvol=@nixos/nix" "noatime" ];
    };
    # Top level at TOS's path so share paths (and Plex's library DB) stay valid.
    "/mnt/md0" = {
      device = data;
      fsType = "btrfs";
      options = [ "subvolid=5" "noatime" ];
    };
    "/home" = {
      device = data;
      fsType = "btrfs";
      options = [ "subvol=User" "noatime" ];
    };
    # ext4 on md9, read by the flash's GRUB (readme: Boot).
    "/boot" = {
      device = "/dev/disk/by-label/KAGOBOOT";
      fsType = "ext4";
    };
  };

  swapDevices = [ { device = "/dev/md/swap"; } ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
