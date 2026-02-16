{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/mino.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets."wifi-psk/Perry7" = {};
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 10;
  boot.kernelParams = [ "console=ttyS0,19200n8" ];

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
    environment = {
      # Location for temporary files
      TMPDIR = "/var/cache/nix";
    };
    serviceConfig = {
      # Create /var/cache/nix automatically on Nix Daemon start
      CacheDirectory = "nix";
    };
  };

  # Even root should use the daemon for builds to avoid /tmp cache
  environment.variables.NIX_REMOTE = "daemon";

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

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  networking = {
    hostName = "mino";

    vlans = {
      mgmt = {
        id = 10;
        interface = "enp2s0";
      };
      loc = {
        id = 20;
        interface = "enp2s0";
      };
      guest = {
        id = 30;
        interface = "enp2s0";
      };
    };

    interfaces = {
      enp2s0 = {
        useDHCP = false;
      };

      enp4s0 = {
        useDHCP = true;
      };

      mgmt.ipv4.addresses = [
        { address = "10.0.1.1"; prefixLength = 24; }
      ];

      loc.ipv4.addresses = [
        { address = "10.0.2.1"; prefixLength = 24; }
      ];

      guest.ipv4.addresses = [
        { address = "10.0.3.1"; prefixLength = 24; }
      ];
    };

    wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi-psk/Perry7".path;
      networks = {
        "Shady Acres - Guest" = {
        };
        "Perry7" = {
          pskRaw = "ext:wifi_psk";
        };
      };
    };

    dhcpcd = {
      enable = true;
      persistent = true; # keep interface configuration on daemon shutdown.
      allowInterfaces = [ "enp4s0" "wlo1" ];
      extraConfig = ''
        # generate a RFC 4361 complient DHCP ID
        duid

        # We don't want to expose our hw addr from the router to the internet,
        # so we generate a RFC7217 address.
        slaac private

        # Default to no ipv6
        noipv6rs

        # settings for the interface
        interface enp4s0
          ipv6rs              # router advertisement solicitaion
          iaid 1              # interface association ID
          ia_na 1             # Request an address
          ia_pd 2 mgmt/0 loc/1 guest/2       # request PDs for interfaces
      '';
    };

    nat = {
      enable = true;
      internalInterfaces = [
        "mgmt"
        "loc"
        "guest"
      ];
      externalInterface = "enp4s0";
    };

    nftables = {
      enable = true;
    };

    firewall = {
      enable = true;
      allowedTCPPorts = [
        53 #DNS
      ];
      allowedUDPPorts = [
        53 #DNS
        67 #DHCP
      ];
    };
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      interface = [
        "enp2s0"
        "mgmt"
        "loc"
        "guest"
      ];
      dhcp-range = [
        "enp2s0,192.168.1.100,192.168.1.254,1h"
        "mgmt,10.0.1.30,10.0.1.254,36h"
        "loc,10.0.2.20, 10.0.2.254,36h"
        "guest,10.0.3.10,10.0.3.254,5h"
      ];
      dhcp-host = [
        "duck,10.0.1.3"
        "bones,10.0.2.10"
      ];
    };
  };

  services.radvd = {
    enable = true;
    config = ''
      interface mgmt {
        AdvSendAdvert on;
        MinRtrAdvInterval 3;
        MaxRtrAdvInterval 10;
        prefix ::/64 {
          AdvOnLink on;
          AdvAutonomous on;
          AdvRouterAddr on;
          AdvValidLifetime 3600;
          AdvPreferredLifetime 3600;
        };
      };
      interface loc {
        AdvSendAdvert on;
        MinRtrAdvInterval 3;
        MaxRtrAdvInterval 10;
        prefix ::/64 {
          AdvOnLink on;
          AdvAutonomous on;
          AdvRouterAddr on;
          AdvValidLifetime 3600;
          AdvPreferredLifetime 3600;
        };
      };
      interface guest {
        AdvSendAdvert on;
        MinRtrAdvInterval 3;
        MaxRtrAdvInterval 10;
        prefix ::/64 {
          AdvOnLink on;
          AdvAutonomous on;
          AdvRouterAddr on;
          AdvValidLifetime 3600;
          AdvPreferredLifetime 3600;
        };
      };
    '';
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    domainName = "local";
    publish = {
      enable = true;
      domain = true;
      addresses = true;
      workstation = true;
    };
  };

  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  users.mutableUsers = false;

  users.users.josh = {
    uid = 1000;
    group = "josh";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsPaFplk95wdbZnGF9q1LnQUKy36Lh+4dSHyFJwMeUK josh@6bit.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4wKwiX1fnwB/U4Mc7JT4ddMExopexk0DUSd7Du12Sp ada@signi"
    ];
  };

  users.groups.josh = {
   gid = 1000;
  };

  system.stateVersion = "23.05";

}
