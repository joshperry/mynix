# NixOS-in-RAM environment for kago, entered from TOS by kexec (see ../readme.md).
# Build: nix build ./machines/kago/kexec
{
  inputs.nixos-images.url = "github:nix-community/nixos-images/50939ddf1a0339f289a9dbd810bdfd4e4fba6df4";
  inputs.nixpkgs.follows = "nixos-images/nixos-stable";

  outputs = { nixos-images, nixpkgs, ... }: {
    packages.x86_64-linux.default =
      (nixpkgs.legacyPackages.x86_64-linux.nixos [
        nixos-images.nixosModules.kexec-installer
        nixos-images.nixosModules.noninteractive
        ({ config, pkgs, ... }: {
          system.kexec-installer.name = "kago-kexec";
          networking.hostName = "kago";

          # Keep the pinned [kago.local]:9222 host key valid: host keys are
          # carried over from TOS by kexec-run, port and mDNS name match.
          services.openssh.ports = [ 22 9222 ];
          services.avahi = {
            enable = true;
            nssmdns4 = true;
            publish = { enable = true; addresses = true; };
          };

          # Never auto-assemble the data RAID; everything is assembled by hand, read-only.
          boot.swraid.enable = pkgs.lib.mkForce false;
          boot.kernelParams = [ "raid=noautodetect" ];

          # IT8613E fan controller (not in mainline it87) and HDD temps.
          boot.extraModulePackages = [ config.boot.kernelPackages.it87 ];

          # Only the Realtek NIC firmware (r8169 onboard, r8152 USB dongle).
          hardware.firmware = [
            (pkgs.runCommand "rtl-nic-firmware" { } ''
              mkdir -p $out/lib/firmware
              cp -r ${pkgs.linux-firmware}/lib/firmware/rtl_nic $out/lib/firmware/
            '')
          ];

          environment.systemPackages = with pkgs; [
            mdadm lvm2 btrfs-progs smartmontools lm_sensors pciutils usbutils gptfdisk ethtool
          ];
        })
      ]).config.system.build.kexecInstallerTarball;
  };
}
