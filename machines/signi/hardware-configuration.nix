# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelPackages = pkgs.linuxPackages_6_15;
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."mainenc".device = "/dev/disk/by-uuid/e464c097-5f99-4eab-b453-f43186b0f38e";

  fileSystems."/" =
    { device = "none";
      fsType = "tmpfs";
      options = [ "noatime" "size=25%" "mode=755" ];
    };
    
  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/108E-66E9";
      fsType = "vfat";
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/38b243a0-c875-4758-8998-cc6c6a4c451e";
      fsType = "btrfs";
      options = [ "subvol=@nix" "noatime" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/38b243a0-c875-4758-8998-cc6c6a4c451e";
      fsType = "btrfs";
      options = [ "subvol=@home" "noatime" ];
    };

  fileSystems."/persist" =
    { device = "/dev/disk/by-uuid/38b243a0-c875-4758-8998-cc6c6a4c451e";
      fsType = "btrfs";
      neededForBoot = true;
      options = [ "subvol=@persist" "noatime" ];
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp2s0f0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
