{ pkgs, lib, config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../profiles/server.nix
    ../../profiles/seed-cache.nix
  ];

  options.seed.vpcSubnets = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    description = "VPC CIDRs allowed to reach Tang (one per cluster)";
  };

  config = {
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    sops.secrets.vultr-api-key = {
      sopsFile = ../../secrets/seed-puncher-1.yaml;
    };
    # pdns API key is generated at boot — only used locally (pdns ↔ sync script)

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # Tang: Network-Bound Disk Encryption server
    # Nodes auto-unlock LUKS by contacting this server at boot.
    services.tang = {
      enable = true;
      listenStream = [ "7654" ];
      ipAddressAllow = config.seed.vpcSubnets;
    };

    # Generate tang keys on first boot (DynamicUser tangd can't create them itself)
    systemd.services.tangd-keygen = {
      description = "Generate Tang keys if missing";
      wantedBy = [ "tangd.socket" ];
      before = [ "tangd.socket" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecCondition = "${pkgs.bash}/bin/bash -c '[ ! -d /var/lib/private/tang ] || [ -z \"$(ls -A /var/lib/private/tang 2>/dev/null)\" ]'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p /var/lib/private/tang && ${pkgs.tang}/libexec/tangd-keygen /var/lib/private/tang'";
      };
    };

    # --- DNS: unbound (recursive resolver) + pdns (authoritative for combine.loom.farm) ---

    # PowerDNS: authoritative for combine.loom.farm, localhost-only.
    # Records are managed by the combine-dns-sync timer via HTTP API.
    services.powerdns = {
      enable = true;
      extraConfig = ''
        launch=gsqlite3
        gsqlite3-database=/var/lib/pdns/combine.sqlite
        local-address=127.0.0.1
        local-port=5300
        socket-dir=/run/pdns
        api=yes
        webserver=yes
        webserver-address=127.0.0.1
        webserver-port=8081
        webserver-allow-from=127.0.0.0/8
        include-dir=/run/pdns/conf.d
      '';
    };

    # pdns needs /run/pdns for its control socket
    systemd.services.pdns.serviceConfig.RuntimeDirectory = "pdns";

    # Initialize pdns SQLite DB + API key before pdns starts
    systemd.services.pdns.serviceConfig.ExecStartPre = let
      script = pkgs.writeShellScript "pdns-init" ''
        mkdir -p /run/pdns/conf.d

        # Initialize SQLite DB with pdns schema if it doesn't exist
        DB=/var/lib/pdns/combine.sqlite
        if [ ! -f "$DB" ]; then
          ${pkgs.sqlite}/bin/sqlite3 "$DB" < ${pkgs.pdns}/share/doc/pdns/schema.sqlite3.sql
          chown pdns:pdns "$DB"
        fi

        # Clean up stale pdns metadata (prevents startup warnings on 4.9.x)
        ${pkgs.sqlite}/bin/sqlite3 "$DB" "DELETE FROM domainmetadata WHERE kind='SOA-EDIT-DNSUPDATE';" 2>/dev/null || true
        ${pkgs.sqlite}/bin/sqlite3 "$DB" "DELETE FROM domainmetadata WHERE kind='INCEPTION-INCREMENT';" 2>/dev/null || true

        # Generate API key if not already present (persists across pdns restarts within same boot)
        if [ ! -f /run/pdns/api-key ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 16 > /run/pdns/api-key
          chmod 600 /run/pdns/api-key
        fi
        echo "api-key=$(cat /run/pdns/api-key)" > /run/pdns/conf.d/api-key.conf
      '';
    in "+${script}"; # + prefix runs as root

    # Ensure pdns SQLite DB directory exists with correct ownership
    systemd.tmpfiles.rules = [
      "d /var/lib/pdns 0750 pdns pdns -"
    ];

    # Unbound: recursive resolver, serves as sole nameserver for seed nodes.
    # Forwards combine.loom.farm to local pdns, everything else to public resolvers.
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "0.0.0.0" "::" ];
          access-control = [
            "10.0.0.0/24 allow"
            "127.0.0.0/8 allow"
            "::1/128 allow"
          ];
          # Allow forwarding to localhost (pdns on 127.0.0.1:5300)
          do-not-query-localhost = false;
          # Disable DNSSEC for combine.loom.farm (internal zone, no signing)
          domain-insecure = [ "combine.loom.farm" ];
        };
        forward-zone = [
          {
            name = "combine.loom.farm.";
            forward-addr = [ "127.0.0.1@5300" ];
          }
          {
            name = ".";
            forward-addr = [ "1.1.1.1" "1.0.0.1" ];
          }
        ];
      };
    };

    # --- combine-dns-sync: Vultr API poller → pdns record updates ---

    systemd.services.combine-dns-sync = {
      description = "Sync Vultr hosts to combine.loom.farm DNS";
      after = [ "pdns.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [ curl jq ];
      environment = {
        VULTR_API_KEY_FILE = config.sops.secrets.vultr-api-key.path;
        PDNS_API_KEY_FILE = "/run/pdns/api-key";
        ALIASES_FILE = "${./combine-dns/aliases.json}";
        ZONE = "combine.loom.farm.";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${./combine-dns/sync.sh}";
        # Run as root to read sops secrets
        User = "root";
      };
    };

    systemd.timers.combine-dns-sync = {
      description = "Poll Vultr API and update DNS every 60s";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "60s";
        RandomizedDelaySec = "5s";
      };
    };

    networking = {
      hostName = "seed-puncher-1";
      useDHCP = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22    # SSH
          53    # DNS (unbound)
          7654  # Tang
        ];
        allowedUDPPorts = [
          53    # DNS (unbound)
        ];
      };
    };

    time.timeZone = "America/Chicago";
    i18n.defaultLocale = "en_US.UTF-8";

    environment.systemPackages = with pkgs; [
      inetutils
      dig
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
  };
}
