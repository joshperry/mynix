{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Tang: Network-Bound Disk Encryption server
  # Nodes auto-unlock LUKS by contacting this server at boot.
  # Keys auto-generated on first start — back up /var/db/tang/
  services.tang = {
    enable = true;
    listenStream = [ "7654" ];
    ipAddressAllow = [
      "216.128.140.0/23"   # seed-dfw-1 subnet
      "104.238.146.0/23"   # seed-dfw-2 subnet
      "45.76.238.0/23"     # seed-dfw-3 subnet
    ];
  };

  networking = {
    hostName = "seed-tang-1";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22    # SSH
        7654  # Tang
      ];
    };
  };

  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    inetutils
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  users.mutableUsers = false;

  users.users.josh = {
    uid = 1000;
    group = "josh";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsPaFplk95wdbZnGF9q1LnQUKy36Lh+4dSHyFJwMeUK josh@6bit.com"
    ];
  };
  users.groups.josh = { gid = 1000; };

  users.users.ada = {
    uid = 1100;
    group = "ada";
    isNormalUser = true;
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4wKwiX1fnwB/U4Mc7JT4ddMExopexk0DUSd7Du12Sp ada@signi"
    ];
  };
  users.groups.ada = { gid = 1100; };

  security.sudo.extraRules = [{
    users = [ "ada" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  system.stateVersion = "25.11";
}
