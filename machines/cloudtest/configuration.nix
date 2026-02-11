{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
  ];

  # GCE uses GRUB with BIOS boot (no EFI on most instance types)
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };
  boot.loader.timeout = 5;

  # GCE serial console
  boot.kernelParams = [ "console=ttyS0,115200n8" ];

  networking.hostName = "cloudtest";
  time.timeZone = "MST7MDT";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    inetutils
    mtr
    sysstat
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  networking.firewall.enable = true;

  users.users.josh = {
    uid = 1000;
    group = "josh";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsPaFplk95wdbZnGF9q1LnQUKy36Lh+4dSHyFJwMeUK josh@6bit.com"
    ];
  };

  users.groups.josh = {
    gid = 1000;
  };

  system.stateVersion = "25.11";
}
