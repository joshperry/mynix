{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
    ../../profiles/seed-cache.nix
  ];

  options.seed.netbootPath = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Path to the seed-netboot derivation (bzImage + initrd) for iPXE serving";
  };

  config = {
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Stake runs Pulumi + nixos-anywhere locally to provision cluster nodes.
    # Builds closures locally (with S3 binary cache from seed-cache.nix) and
    # transfers them to targets in-datacenter via nixos-anywhere --build-on local.
    environment.systemPackages = with pkgs; [
      nodejs_22       # Pulumi runtime + provision-cluster.ts
      pulumi-bin      # Pulumi CLI
      nixos-anywhere  # Remote NixOS installation
      sops            # Secret decryption
      age             # age encryption (sops backend)
      ssh-to-age      # SSH key → age key conversion
      jq              # JSON processing
      git             # Clone repos
    ];

    # Serve netboot artifacts (kernel + initrd) over plain HTTP for iPXE.
    # iPXE on Vultr can't validate Let's Encrypt TLS certs, so we serve
    # over HTTP from stake (port 8080). The netboot derivation is in the
    # nix store — no mutable state needed.
    services.nginx = lib.mkIf (config.seed.netbootPath != null) {
      enable = true;
      virtualHosts."netboot" = {
        listen = [{ addr = "0.0.0.0"; port = 8080; }];
        root = "${config.seed.netbootPath}";
        extraConfig = ''
          autoindex on;
        '';
      };
    };

    # Registration endpoint: receives phone-home POSTs from machines that
    # iPXE-booted from our netboot endpoint. Writes registrations to
    # /var/lib/seed-register/<mac>.json for the provision-cluster script
    # to watch via inotify.
    systemd.services.seed-register = {
      description = "Seed machine registration endpoint";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${./register-server.mjs}";
        Restart = "always";
        StateDirectory = "seed-register";
      };
    };

    networking = {
      hostName = "seed-stake";
      useDHCP = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22    # SSH
          8080  # Netboot HTTP (iPXE)
          8081  # Registration endpoint
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
