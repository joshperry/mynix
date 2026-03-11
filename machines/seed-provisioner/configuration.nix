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

    # --- SSH substituter proxy ---
    # Serves the local nix store over SSH. The local store is backed by
    # the S3 binary cache (via seed-cache.nix), so clients transparently
    # get paths from S3 without needing credentials themselves.
    #
    # Usage from clients:
    #   nix build --substituters "ssh-ng://nix-ssh@<provisioner-ip>" ...
    nix.sshServe = {
      enable = true;
      keys = [
        # ada@signi — for running nixos-anywhere from signi
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4wKwiX1fnwB/U4Mc7JT4ddMExopexk0DUSd7Du12Sp ada@signi"
        # josh@6bit.com — for manual provisioning
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsPaFplk95wdbZnGF9q1LnQUKy36Lh+4dSHyFJwMeUK josh@6bit.com"
      ];
      # Allow write access so the post-build-hook can upload to S3 cache
      # after building on the provisioner
      write = true;
    };

    # S3 credentials for nix-daemon are provided by seed-cache.nix.
    # nix-store --serve (ForceCommand for nix-ssh user) communicates with
    # nix-daemon which handles substituter fetches — no extra config needed.

    networking = {
      hostName = "seed-provisioner";
      useDHCP = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22 # SSH (admin + nix-ssh substituter)
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
