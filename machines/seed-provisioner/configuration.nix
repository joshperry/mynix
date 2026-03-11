{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
    ../../profiles/seed-cache.nix
  ];

  config = {
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Provisioner runs Pulumi + nixos-anywhere locally to provision cluster nodes.
    # Builds closures locally (with S3 binary cache from seed-cache.nix) and
    # transfers them to targets in-datacenter via nixos-anywhere --build-on local.
    environment.systemPackages = with pkgs; [
      nodejs_22       # Pulumi runtime
      pulumi-bin      # Pulumi CLI
      nixos-anywhere  # Remote NixOS installation
      sops            # Secret decryption
      age             # age encryption (sops backend)
      ssh-to-age      # SSH key → age key conversion
      jq              # JSON processing
      git             # Clone repos
    ];

    networking = {
      hostName = "seed-provisioner";
      useDHCP = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22 # SSH
        ];
      };
    };

    time.timeZone = "America/Chicago";
    i18n.defaultLocale = "en_US.UTF-8";

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
  };
}
