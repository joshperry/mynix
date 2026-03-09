{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
    ../../profiles/seed-cache.nix
    ../../profiles/seed-ceph.nix
    ../../profiles/seed-controller.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/seed-dfw-3.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets."seed/k3s-token" = {};
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  # Console on both VGA (KVM) and serial — VGA needed for LUKS passphrase prompt
  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200n8" ];

  # Allow ada to push closures for remote deploys
  nix.settings.trusted-users = [ "root" "ada" ];

  # Seed: k3s HA bootstrap node (first server, etcd init)
  seed = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets."seed/k3s-token".path;
    persistence.enable = true;
    persistence.path = "/persist";
    k3s.clusterInit = true;
    k3s.dualStack = true;
    k3s.extraFlags = [
      "--node-ip=45.76.239.250,2001:19f0:6401:a11:3eec:efff:feb9:84bc"
    ];
  };

  # Impermanence mappings
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/var/cache/nix"
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
    ];
  };

  # Don't build in /tmp ramdisk
  systemd.services.nix-daemon = {
    environment.TMPDIR = "/var/cache/nix";
    serviceConfig.CacheDirectory = "nix";
  };
  environment.variables.NIX_REMOTE = "daemon";

  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "github:joshperry/mynix";
    allowReboot = true;
  };

  networking = {
    hostName = "seed-dfw-3";
    interfaces.enp1s0f0 = {
      useDHCP = true;
      ipv6.addresses = [
        { address = "2001:19f0:6401:a11:3eec:efff:feb9:84bc"; prefixLength = 64; }
      ];
    };
    defaultGateway6 = {
      address = "fe80::63f:72ff:fe74:47bc";
      interface = "enp1s0f0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22    # SSH
        6443  # k3s API
      ];
    };
  };

  time.timeZone = "America/Chicago";
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
