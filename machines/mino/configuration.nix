{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/mino.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.wifi-psk = {};
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

  # Wifi and starlink are mutually exclusive WANs. When wifi connects,
  # take down ethernet so all traffic (v4 and v6) goes through wifi.
  # When wifi drops, bring ethernet back for starlink.
  systemd.services.wifi-wan-switch = {
    description = "Switch between wifi and starlink WAN";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      prev_state=""
      check_wifi() {
        ip route show default dev wlo1 2>/dev/null | grep -q .
      }
      update() {
        if check_wifi; then
          if [ "$prev_state" != "wifi" ]; then
            echo "wifi WAN active, taking down starlink"
            systemctl stop radvd || true
            ip link set enp4s0 down || true
            # Flush stale v6 prefixes from VLAN interfaces
            ip -6 addr flush dev mgmt scope global || true
            ip -6 addr flush dev loc scope global || true
            ip -6 addr flush dev guest scope global || true
            # Delete starlink lease files (contain cached PD) and restart dhcpcd
            rm -f /var/lib/dhcpcd/enp4s0.lease* || true
            systemctl restart dhcpcd || true
            # Wait for dhcpcd to settle, then start radvd fresh
            sleep 5
            systemctl start radvd || true
            prev_state=wifi
          fi
        else
          if [ "$prev_state" != "starlink" ]; then
            echo "wifi WAN inactive, bringing up starlink"
            systemctl stop radvd || true
            ip link set enp4s0 up || true
            # Give dhcpcd time to get PD from starlink
            sleep 5
            systemctl start radvd || true
            prev_state=starlink
          fi
        fi
      }
      update
      ip monitor route | while read -r line; do
        case "$line" in
          *wlo1*|*"default"*) update ;;
        esac
      done
    '';
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
    flake = "github:joshperry/mynix";
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
      secretsFile = config.sops.secrets.wifi-psk.path;
      networks = {
        "Shady Acres - Guest" = {
        };
        "Perry7" = {
          pskRaw = "ext:wifi_psk";
        };
        "Village Camp" = {
          pskRaw = "ext:village_camp_psk";
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

        # Starlink ethernet — fallback WAN
        interface enp4s0
          metric 200
          ipv6rs              # router advertisement solicitaion
          iaid 1              # interface association ID
          ia_na 1             # Request an address
          ia_pd 2 mgmt/0 loc/1 guest/2       # request PDs for interfaces

        # Campground/park wifi — preferred WAN when connected
        interface wlo1
          metric 100
      '';
    };

    # NAT for starlink WAN
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
      # NAT for wifi WAN (supplements networking.nat which only handles enp4s0)
      tables.wifi-nat = {
        family = "ip";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat + 1; policy accept;
            iifname { "mgmt", "loc", "guest" } oifname "wlo1" masquerade
          }
        '';
      };
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
      # Allow forwarding from internal VLANs to wifi WAN
      # (networking.nat handles enp4s0 forwarding)
      extraForwardRules = ''
        iifname { "mgmt", "loc", "guest" } oifname "wlo1" accept
        iifname "wlo1" oifname { "mgmt", "loc", "guest" } ct state established,related accept
      '';
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
        AdvDefaultLifetime 1800;
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
        AdvDefaultLifetime 1800;
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
        AdvDefaultLifetime 1800;
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
    ];
  };

  users.groups.josh = {
   gid = 1000;
  };

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
    commands = [
      { command = "/nix/store/*/bin/switch-to-configuration"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-env"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/iw"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/wpa_cli"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/ip"; options = [ "NOPASSWD" ]; }
    ];
  }];

  system.stateVersion = "23.05";

}
