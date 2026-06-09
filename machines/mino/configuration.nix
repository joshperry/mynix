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
    # Wifi PSKs, consumed as a NetworkManager ensureProfiles environmentFile
    # (name=value lines, substituted into $var psk placeholders at activation).
    # Read by the ensure-profiles activation as root, so default root:root 0400.
    secrets.wifi-psk = {
      restartUnits = [ "NetworkManager.service" ];
    };
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 10;
  # pcie_port_pm=off: kernel 6.18 (26.05) can't bring the second Realtek NIC
  # (enp4s0, 04:00.0 behind root port 00:1d.3) back from D3cold, so it fails to
  # probe ("Unable to change power state from D3cold to D0"). 6.12 was fine.
  # Disabling PCIe port power management keeps the slot powered. Testing.
  boot.kernelParams = [ "console=ttyS0,19200n8" "pcie_port_pm=off" "panic=10" ];

  # Hardware watchdog fail-safe: if a bisect one-shot boot hangs the kernel
  # (no console access here), the watchdog reboots back into the default
  # generation. panic=10 above reboots 10s after a panic.
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  # Impermanence mappings
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/var/cache/nix"
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      # Runtime-joined park wifi (Cockpit/nmcli) + NM state (seen BSSIDs,
      # connection timestamps) — so ad-hoc joins survive a cold boot.
      "/etc/NetworkManager/system-connections"
      "/var/lib/NetworkManager"
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
            # Stop radvd FIRST while PD is still on VLANs — this
            # ensures the deprecating RA includes the prefix with
            # lifetime 0, so clients drop their SLAAC addresses.
            systemctl stop radvd || true
            ip link set enp4s0 down || true
            # Wait for dhcpcd to drop PD from VLANs
            for i in $(seq 1 15); do
              if ! ip -6 addr show dev mgmt scope global 2>/dev/null | grep -q inet6 \
              && ! ip -6 addr show dev loc scope global 2>/dev/null | grep -q inet6 \
              && ! ip -6 addr show dev guest scope global 2>/dev/null | grep -q inet6; then
                break
              fi
              sleep 1
            done
            # If wifi provides v6 prefixes, start radvd
            if ip -6 addr show dev mgmt scope global 2>/dev/null | grep -q inet6 \
            || ip -6 addr show dev loc scope global 2>/dev/null | grep -q inet6 \
            || ip -6 addr show dev guest scope global 2>/dev/null | grep -q inet6; then
              echo "v6 prefixes available, starting radvd"
              systemctl start radvd || true
            fi
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

  # Allow ada to push pre-built closures from signi (kernel bisect: build
  # the heavy kernels on signi, copy them here, boot via systemd-boot one-shot).
  nix.settings.trusted-users = [ "root" "ada" ];

  system.autoUpgrade = {
    enable = false;
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

    # wlo1 (campground/park wifi uplink) is managed by NetworkManager so parks
    # can be scanned and joined at runtime (Cockpit web UI) without a rebuild —
    # critical when offline at a new site. NM owns ONLY wlo1; every wired iface
    # is unmanaged so the VLANs/SSH path stay on the static config + dhcpcd.
    networkmanager = {
      enable = true;
      # NM registers wlo1's park DNS via resolvconf, exactly as dhcpcd did, so
      # dnsmasq keeps forwarding to the active WAN's resolvers. NOT "none".
      dns = "default";
      unmanaged = [
        "interface-name:enp2s0"
        "interface-name:enp4s0"
        "interface-name:mgmt"
        "interface-name:loc"
        "interface-name:guest"
      ];
      # Known parks declared here as fallback; runtime-joined ones land in
      # /etc/NetworkManager/system-connections (persisted). PSKs come from the
      # sops env file via $var placeholders, never the world-readable store.
      ensureProfiles = {
        environmentFiles = [ config.sops.secrets.wifi-psk.path ];
        profiles =
          let
            wpa = id: ssid: psk: {
              connection = { inherit id; type = "wifi"; };
              wifi = { inherit ssid; mode = "infrastructure"; };
              wifi-security = { key-mgmt = "wpa-psk"; inherit psk; };
              ipv4.method = "auto";
              ipv6.method = "auto";
            };
          in
          {
            perry7 = wpa "Perry7" "Perry7" "$wifi_psk";
            village-camp = wpa "Village Camp" "Village Camp" "$village_camp_psk";
            ccrvpguest = wpa "CCRVPGUEST" "CCRVPGUEST" "$ccrvpguest";
            # Phone "mars" 5GHz hotspot — cellular WAN uplink fallback.
            mars = wpa "mars" "mars" "$mars_psk";
            # Open guest SSID — no wifi-security block.
            shady-acres = {
              connection = { id = "Shady Acres - Guest"; type = "wifi"; };
              wifi = { ssid = "Shady Acres - Guest"; mode = "infrastructure"; };
              ipv4.method = "auto";
              ipv6.method = "auto";
            };
          };
      };
    };

    dhcpcd = {
      enable = true;
      persistent = false;
      # wlo1 is managed by NetworkManager now (handles its own DHCP + resolvconf).
      allowInterfaces = [ "enp4s0" ];
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
      # Cockpit web UI — only reachable from the loc VLAN. This firewall rule
      # is the sole access control (the cockpit module force-resets any
      # socket-level ListenStream bind). Never opened on mgmt/guest/wlo1/WAN.
      interfaces.loc.allowedTCPPorts = [ 9090 ];
      # Allow forwarding from internal VLANs to wifi WAN
      # (networking.nat handles enp4s0 forwarding)
      extraForwardRules = ''
        iifname { "mgmt", "loc", "guest" } oifname "wlo1" accept
        iifname "wlo1" oifname { "mgmt", "loc", "guest" } ct state established,related accept
      '';
    };
  };

  # Cockpit: web UI for system metrics + scanning/joining park wifi at runtime
  # (its Networking panel drives NetworkManager). Access is restricted to the
  # loc VLAN by the firewall rule above (interfaces.loc.allowedTCPPorts); the
  # module's openFirewall is off, so the port is never opened on mgmt/guest/WAN.
  # Auth is PAM (josh/ada). Socket-level bind to 10.0.2.1 isn't done because the
  # cockpit module force-resets ListenStream after any override.
  # Performance Co-Pilot backs Cockpit's metrics *history* (the "PCP is
  # missing" banner). pmcd collects live metrics; pmlogger writes archives.
  # Package + module come from an unmerged nixpkgs PR pinned in flake.nix.
  # pmcd is loopback-only — Cockpit reads it locally, nothing on the LAN.
  # Archives land in /var/log/pcp (already persisted) so history survives
  # impermanence reboots.
  services.pcp = {
    enable = true;
    preset = "minimal"; # pmcd only...
    pmlogger.enable = true; # ...plus archives, which is what Cockpit history needs
    openFirewall = false;
    allowedNetworks = [ "127.0.0.1/32" "::1/128" ];
  };

  services.cockpit = {
    enable = true;
    port = 9090;
    # Cockpit rejects the session WebSocket if the browser Origin isn't in
    # this allow-list (CSRF guard). List every loc-VLAN name/IP it's reached by;
    # mkForce because the module hardcodes only localhost.
    settings.WebService.Origins = lib.mkForce "https://mino.lan:9090 https://10.0.2.1:9090 https://localhost:9090";
  };

  # Bridge PCP's python bindings into cockpit's metrics-history bridge.
  # cockpit-bridge (pcp.py) does `import cpmapi`, but NixOS isolates each
  # derivation's site-packages. The cockpit module links each plugin's
  # passthru.cockpitPath /lib into /etc/cockpit/lib, which is on the bridge's
  # PYTHONPATH — so we add PCP as a plugin carrying a slim env of just its
  # python3.12 bindings (built with python312 in flake.nix to match cockpit's
  # interpreter ABI). cpmapi.so finds libpcp via its store RPATH, so only the
  # site-packages needs linking, not the shared libs. No cockpit rebuild.
  services.cockpit.plugins =
    let
      pcpCockpitLib = pkgs.buildEnv {
        name = "pcp-cockpit-pylib";
        paths = [ config.services.pcp.package ];
        pathsToLink = [ "/lib/python3.12/site-packages" ];
      };
    in
    [
      (config.services.pcp.package // {
        passthru = (config.services.pcp.package.passthru or { }) // {
          cockpitPath = [ pcpCockpitLib ];
        };
      })
    ];

  services.dnsmasq = {
    enable = true;
    settings = {
      interface = [
        "enp2s0"
        "mgmt"
        "loc"
        "guest"
      ];
      # Authoritative local "lan" zone: answered here, never forwarded upstream.
      # DHCP leases and dhcp-host names get <name>.lan via expand-hosts.
      # no-hosts keeps mino's loopback /etc/hosts entries off the LAN; mino's own
      # name is pinned to its loc-VLAN address explicitly.
      domain = "lan";
      local = "/lan/";
      expand-hosts = true;
      domain-needed = true;
      bogus-priv = true;
      no-hosts = true;
      host-record = [ "mino.lan,10.0.2.1" ];
      dhcp-range = [
        "enp2s0,192.168.1.100,192.168.1.254,1h"
        "mgmt,10.0.1.30,10.0.1.254,36h"
        "loc,10.0.2.20, 10.0.2.254,36h"
        "guest,10.0.3.10,10.0.3.254,5h"
      ];
      dhcp-host = [
        # mgmt-plane infrastructure (static reservations below the .30 pool start)
        "3C:8C:F8:15:6B:F0,trendnet,10.0.1.2" # TEG-S80ES switch
        "duck,10.0.1.3" # UniFi CloudKey Gen2
        "74:AC:B9:D2:7A:83,u6lr,10.0.1.4" # UniFi U6-LR AP
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
    # networkmanager: polkit perms for a remote Cockpit session to join/forget wifi.
    extraGroups = [ "wheel" "networkmanager" ];
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

  # Dedicated Cockpit web login so josh needn't use his real creds over the
  # self-signed link. In networkmanager ONLY (not wheel): the NM polkit rule
  # lets it scan/join/forget park wifi via Cockpit, but it cannot sudo,
  # switch configs, or escalate. No SSH key — Cockpit-web-only, never a shell.
  users.users.netadmin = {
    uid = 1200;
    group = "netadmin";
    isNormalUser = true;
    hashedPassword = "$6$d0suRGLMKyO0bdwz$Au4badDzgE.zt0l0.sXbejLHjN3XV2aaKWH0BppITpNnV4w9VziA6TqEtidXPGkGFrnfbV/mOv7MoRQYOvAY81";
    extraGroups = [ "networkmanager" ];
  };
  users.groups.netadmin = { gid = 1200; };

  security.sudo.extraRules = [{
    users = [ "ada" ];
    commands = [
      { command = "/nix/store/*/bin/switch-to-configuration"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-env"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/iw"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/wpa_cli"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/ip"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/journalctl"; options = [ "NOPASSWD" ]; }
      # Kernel-bisect fail-safe: set a one-shot boot entry then reboot. The
      # persistent default stays the known-good generation, so a hung test
      # boot self-recovers via watchdog/panic without console access.
      { command = "/run/current-system/sw/bin/bootctl"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl reboot"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/reboot"; options = [ "NOPASSWD" ]; }
    ];
  }];

  system.stateVersion = "23.05";

}
