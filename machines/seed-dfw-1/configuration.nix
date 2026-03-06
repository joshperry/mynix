{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/signi.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  # Serial console for Vultr KVM/IPMI
  boot.kernelParams = [ "console=ttyS0,115200n8" ];

  # Allow ada to push closures for remote deploys
  nix.settings.trusted-users = [ "root" "ada" ];

  # Seed: k3s + nix-snapshotter + Kata/CLH
  seed = {
    enable = true;
    persistence.enable = true;
    persistence.path = "/persist";
    # servicelb disabled — MetalLB handles LoadBalancer IPs (deployed by seed module)
    k3s.dualStack = true;
    k3s.extraFlags = [
      "--node-ip=216.128.140.15,2001:19f0:6402:d0a:3eec:efff:feb9:c20a"
    ];
    controller = {
      enable = true;
      flakePath = "github:loomtex/seed";
      ipv4Address = "216.128.141.222";
      ipv6Block = "2001:19f0:6402:7eb::/64";
    };
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
    hostName = "seed-dfw-1";
    interfaces.enp1s0f0 = {
      useDHCP = true;
      ipv4.addresses = [{
        address = "216.128.141.222";
        prefixLength = 32;
      }];
      ipv6.addresses = [
        { address = "2001:19f0:6402:d0a:3eec:efff:feb9:c20a"; prefixLength = 64; }
        { address = "2001:19f0:6402:7eb::1"; prefixLength = 64; }
      ];
    };
    defaultGateway6 = {
      address = "fe80::920a:84ff:fe53:f9bc";
      interface = "enp1s0f0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22    # SSH
        53    # DNS (seed ipv4 route)
        6443  # k3s API
      ];
      allowedUDPPorts = [
        53    # DNS (seed ipv4 route)
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
