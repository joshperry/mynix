{ config, pkgs, lib, ... }:
# kago: TerraMaster F5-221 NAS, migrated from TOS 4.2 keeping the TOS data
# volume in place. Research, install and cutover steps: readme.md.
{
  imports = [
    ./hardware-configuration.nix
    ./fan.nix
    ./backup.nix
    ./beep.nix
    ./health.nix
    ../../profiles/server.nix
  ];

  # Boot: BIOS (boot order locked, boots the disks) -> TOS's GRUB in the disks'
  # MBR, config on sdX1 -> /boot on md9. The internal USB flash has the same
  # TOS GRUB. NixOS only maintains grub.cfg and the kernels on /boot and never
  # installs GRUB itself; the TOS GRUBs get a config that hands over to ours.
  boot.loader.grub = {
    enable = true;
    devices = [ "nodev" ];
    copyKernels = true;
    configurationLimit = 10;  # /boot (md9) is 1.9G
    # TOS-era GRUBs load our grub.cfg; keep it to plain text.
    splashImage = null;
    # Keep the TOS GRUBs' configs pointed at ours (original kept as grub.cfg.tos).
    extraInstallCommands = let
      handover = ./usbflash-grub.cfg;
      tosBoot = [
        "/dev/disk/by-id/ata-ST14000NM0018-2H4101_ZHZ680TR-part1"
        "/dev/disk/by-id/ata-ST14000NM0018-2H4101_ZHZ63P8S-part1"
        "/dev/disk/by-id/ata-ST14000NM0018-2H4101_ZHZ5JXXZ-part1"
        "/dev/disk/by-label/UTOSBOOT-X86-S64"  # internal USB flash
      ];
    in ''
      for dev in ${lib.concatStringsSep " " tosBoot}; do
        [ -b "$dev" ] || { echo "kago: $dev missing, skipping"; continue; }
        m=$(${pkgs.coreutils}/bin/mktemp -d)
        ${pkgs.util-linux}/bin/mount "$dev" "$m"
        for cfg in "$m/boot/grub/grub.cfg" "$m/boot/grub2/grub.cfg"; do
          [ -e "$cfg" ] || continue
          if ! ${pkgs.diffutils}/bin/cmp -s ${handover} "$cfg"; then
            # back up only TOS's own config, not an earlier hand-over version
            ${pkgs.gnugrep}/bin/grep -q '^# kago:' "$cfg" || [ -e "$cfg.tos" ] \
              || ${pkgs.coreutils}/bin/cp -a "$cfg" "$cfg.tos"
            ${pkgs.coreutils}/bin/install -m 644 ${handover} "$cfg"
            echo "kago: wrote hand-over grub.cfg to $dev"
          fi
        done
        ${pkgs.util-linux}/bin/umount "$m"
        ${pkgs.coreutils}/bin/rmdir "$m"
      done
    '';
  };

  networking.hostName = "kago";

  time.timeZone = "MST7MDT";
  i18n.defaultLocale = "en_US.UTF-8";

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "plexmediaserver"
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Users. TOS ids (josh 2, janus 5, ada 7, plex 5555, groups admin 3 /
  # allusers 4) are remapped on the data volume during install (readme:
  # Ownership); gid 4 is messagebus on NixOS.
  users.mutableUsers = false;

  users.groups.nas = { gid = 2000; };  # replaces TOS admin (3) + allusers (4)

  users.users.josh = {
    uid = 1000;
    group = "josh";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [ "wheel" "nas" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsPaFplk95wdbZnGF9q1LnQUKy36Lh+4dSHyFJwMeUK josh@6bit.com"
    ];
  };
  users.groups.josh = { gid = 1000; };

  # Samba-only account (no shell login).
  users.users.janus = {
    uid = 1001;
    group = "janus";
    isNormalUser = true;
    hashedPassword = "!";
    extraGroups = [ "nas" ];
  };
  users.groups.janus = { gid = 1001; };

  users.users.ada = {
    uid = 1100;
    group = "ada";
    isNormalUser = true;
    hashedPassword = "!";
    extraGroups = [ "nas" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH4wKwiX1fnwB/U4Mc7JT4ddMExopexk0DUSd7Du12Sp ada@signi"
    ];
  };
  users.groups.ada = { gid = 1100; };

  # 2G RAM: systems are built on signi and copied over, so ada must be able
  # to import unsigned paths. Scoped sudo is enough to deploy.
  nix.settings.trusted-users = [ "ada" ];
  security.sudo.extraRules = [{
    users = [ "ada" ];
    commands = [
      { command = "/nix/store/*/bin/switch-to-configuration"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-env"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/journalctl"; options = [ "NOPASSWD" ]; }
    ];
  }];

  environment.systemPackages = with pkgs; [
    acl
    btrfs-progs
    lm_sensors
    mdadm
    smartmontools
  ];

  # Web status page in place of the TOS UI (log in as josh).
  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = true;
    # Cockpit rejects the session WebSocket unless the browser Origin is listed;
    # mkForce because the module hardcodes only localhost.
    settings.WebService.Origins = lib.mkForce "https://kago.local:9090 https://localhost:9090";
  };

  # Shares, as configured on TOS (smb.conf). Passwords are imported from TOS's
  # smbpasswd into tdbsam during install (readme).
  services.samba = {
    enable = true;
    openFirewall = true;
    nmbd.enable = true;
    settings = let
      share = path: users: {
        inherit path;
        browseable = "yes";
        writeable = "yes";
        "inherit permissions" = "yes";
        "valid users" = users;
        "write list" = users;
      };
      recycle = {
        "vfs objects" = "recycle";
        "recycle:repository" = "./#recycle";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
        "recycle:directory_mode" = "0777";
        "recycle:exclude_dir" = "#recycle";
      };
    in {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "kago";
        "netbios name" = "kago";
        "security" = "user";
        "passdb backend" = "tdbsam";
        "map to guest" = "never";
        "fruit:aapl" = "yes";
      };
      public = share "/mnt/md0/public" "josh janus ada";
      appdata = share "/mnt/md0/appdata" "josh ada";
      media = share "/mnt/md0/media" "josh janus ada" // recycle;
      bu = share "/mnt/md0/bu" "josh" // recycle;
    };
  };
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Existing library, metadata and preferences from TOS (/home/plex there).
  # Reached via the top-level mount: the plex unit has ProtectHome, which hides
  # /home (the User subvolume) from it.
  services.plex = {
    enable = true;
    openFirewall = true;
    dataDir = "/mnt/md0/User/plex/Library/Application Support";
  };
  users.users.plex.extraGroups = [ "nas" ];

  services.transmission = {
    enable = true;
    openRPCPort = true;
    openPeerPorts = true;
    settings = {
      download-dir = "/mnt/md0/public";
      incomplete-dir-enabled = false;
      watch-dir = "/mnt/md0/public/rssseeds";
      watch-dir-enabled = true;
      rpc-bind-address = "0.0.0.0";
      rpc-port = 9091;
      rpc-whitelist-enabled = false;
      rpc-authentication-required = false;
      peer-port = 64622;
      ratio-limit = 2;
      ratio-limit-enabled = true;
      speed-limit-up = 100;
      speed-limit-up-enabled = true;
      umask = "022";
    };
  };
  users.users.transmission.extraGroups = [ "nas" ];

  system.stateVersion = "26.05";
}
