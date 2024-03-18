# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub = {
    enable = true;
    forceInstall = true;
    device = "nodev";
    # linode lish console
    extraConfig = ''
      serial --speed=19200 --unit=0 --word=8 --parity=no --stop=1;
      terminal_input serial;
      terminal_output serial
    '';
  };
  boot.loader.timeout = 10;
  boot.kernelParams = [ "console=ttyS0,19200n8" ];

  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "${config.users.users.josh.home}/dev/mynix";
    flags = [
      "--update-input" "nixpkgs"
    ];
    allowReboot = true;
  };

  environment.systemPackages = with pkgs; [
    inetutils
    mtr
    sysstat
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  networking.firewall = {
    enable = true;
  };

  networking.hostName = "liver";

  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.josh = {
    uid = 1000;
    group = "josh";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/W42ehUPgwbpGOe9agkr1t9m/hNpnxtq77F+DSoxeA josh@6bit.com" ];
  };

  users.groups.josh = {
   gid = 1000;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}
