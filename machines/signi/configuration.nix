({ pkgs, config, lib, ... }:
let
  mkUserDefault = lib.mkOverride 999;
in {
  imports = [
    ./hardware-configuration.nix
    ../../profiles/graphical.nix
  ];

  # ── Secrets (sops-nix) ────────────────────────────────────────
  sops = {
    defaultSopsFile = ../../secrets/signi.yaml;
    age.keyFile = "/run/sops-age/keys.txt";
    secrets."kago/credentials" = { };
    secrets."ada/vultr-api-key" = { };
    secrets."ada/openrouter-api-key" = { };
    secrets."backup/luks-key" = { };
  };

  # ── Nuketown: AI agent framework ──────────────────────────────
  nuketown = {
    enable = true;
    domain = "6bit.com";
    humanUser = "josh";
    btrfsDevice = "38b243a0-c875-4758-8998-cc6c6a4c451e";
    sopsFile = ../../secrets/signi.yaml;

    agents.ada = {
      enable = true;
      uid = 1100;
      role = "software";
      description = ''
        Software collaborator on signi. Works with josh on embedded systems
        (Rotorflight, Betaflight, STM32), NixOS configuration, and web projects.
      '';

      git = {
        name = "Ada";
        email = "ada@6bit.com";
      };

      persist = [
        "projects"
        ".claude"
      ];

      sudo.enable = true;
      portal.enable = true;

      daemon = {
        enable = true;
        apiKeySecret = "ada/anthropic-api-key";
        repos = {
          nuketown = { url = "git@github.com:joshperry/nuketown.git"; };
          mynix = { url = "git@github.com:joshperry/mynix.git"; };
        };
        mail = {
          enable = true;
          host = "mail.6bit.com";
          username = "ada@6bit.com";
          passwordSecret = "ada/email-password";
        };
      };

      xmpp = {
        enable = true;
        jid = "ada@6bit.com";
        passwordSecret = "ada/email-password";
      };

      packages = with pkgs; [
        gh vultr-cli ssh-to-age sops mynix.ada-narrator sox
        python3 openssl file dig iproute2 xxd binutils
        mynix.silo
      ];

      secrets.sshKey = "ada/ssh-key";
      secrets.gpgKey = "ada/gpg-key";
      secrets.extraSecrets.email-password = "ada/email-password";
      secrets.extraSecrets.gh-pat = "ada/gh-pat";
      secrets.extraSecrets.vultr-api-key = "ada/vultr-api-key";
      secrets.extraSecrets.openrouter-api-key = "ada/openrouter-api-key";

      devices = [
        {
          subsystem = "tty";
          action = "add";
          attrs = { idVendor = "0483"; idProduct = "5740"; };
        }
        {
          subsystem = "usb";
          attrs = { product = "STM32  BOOTLOADER"; };
        }
        {
          subsystem = "usb";
          attrs = { product = "DFU in FS Mode"; };
        }
        {
          subsystem = "tty";
          attrs = { idVendor = "303a"; idProduct = "1001"; };
        }
      ];

      claudeCode = {
        enable = true;
        settings = {
          voiceEnabled = true;
          env = {
            CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
            PULSE_SERVER = "tcp:127.0.0.1:4713";
          };
          permissions = {
            defaultMode = "bypassPermissions";
            additionalDirectories = [
              "/home/josh/dev"
            ];
          };
          hooks = {
            Stop = [{
              hooks = [{
                type = "command";
                command = "/etc/profiles/per-user/ada/bin/ada-worklog";
                timeout = 5000;
              }];
            }];
            PostToolUse = [{
              hooks = [{
                type = "command";
                command = "/etc/profiles/per-user/ada/bin/ada-worklog";
                timeout = 5000;
              }];
            }];
          };
        };
      };

      extraHomeConfig = {
        home.stateVersion = "25.11";
        # Portal inner tmux — behavioral settings only, no status/keybindings
        # (status is disabled by the portal launcher, josh's outer tmux handles chrome)
        programs.tmux = {
          enable = true;
          mouse = true;
          keyMode = "vi";
          escapeTime = 0;
          terminal = "tmux-256color";
          historyLimit = 20000;
          extraConfig = ''
            # Match josh's scroll speed
            bind -T copy-mode-vi WheelUpPane select-pane \; send-keys -X -N 2 scroll-up
            bind -T copy-mode-vi WheelDownPane select-pane \; send-keys -X -N 2 scroll-down

            # 24-bit color passthrough
            set -as terminal-features ",xterm-256color:RGB"
            set-option -g focus-events on
          '';
        };
        programs.gpg.enable = true;
        programs.git.signing.key = "6CD1AEABA566EC82";
        # ssh-agent for SSH (GPG agent handles signing only, not SSH)
        services.ssh-agent.enable = true;
        # command-not-found handler: suggest nix run instead of failing silently
        home.file.".local/share/bash/command-not-found.sh".text = ''
          command_not_found_handle() {
            echo "$1: command not found — try: nix run nixpkgs#$1 -- ''${@:2}" >&2
            return 127
          }
        '';
        # Import keys and set env on login
        programs.bash.profileExtra = ''
          export BASH_ENV="$HOME/.local/share/bash/command-not-found.sh"
          export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
          if [ -f ${config.sops.secrets."ada/gpg-key".path} ]; then
            gpg --batch --import ${config.sops.secrets."ada/gpg-key".path} 2>/dev/null || true
          fi
          ssh-add -l &>/dev/null || ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
          export GH_TOKEN="$(cat ${config.sops.secrets."ada/gh-pat".path} 2>/dev/null || true)"
          export VULTR_API_KEY="$(cat ${config.sops.secrets."ada/vultr-api-key".path} 2>/dev/null || true)"
        '';
        accounts.email.accounts.ada = {
          primary = true;
          address = "ada@6bit.com";
          realName = "Ada";
          imap = {
            host = "mail.6bit.com";
            port = 993;
          };
          smtp = {
            host = "mail.6bit.com";
            port = 587;
            tls.useStartTls = true;
          };
          userName = "ada@6bit.com";
          passwordCommand = "cat ${config.sops.secrets."ada/email-password".path}";
          msmtp.enable = true;
          neomutt = {
            enable = true;
            extraConfig = ''
              set sort = reverse-date
            '';
          };
        };
        programs.msmtp.enable = true;
        programs.neomutt.enable = true;
        programs.neovim = {
          enable = true;
          vimAlias = true;
          defaultEditor = true;
        };
        programs.bash.shellAliases = {
          ll = "ls --color=auto";
        };
        # Periodic TTS narrator — summarizes work log every 3 minutes
        systemd.user.services.ada-narrator = {
          Unit.Description = "Ada TTS narrator — periodic work log summary";
          Service = {
            Type = "oneshot";
            ExecStart = "/etc/profiles/per-user/ada/bin/ada-narrator";
            Environment = [
              "PULSE_SERVER=tcp:127.0.0.1:4713"
              "PATH=/etc/profiles/per-user/ada/bin:/run/current-system/sw/bin:/usr/bin:/bin"
            ];
          };
        };
        systemd.user.timers.ada-narrator = {
          Unit.Description = "Ada TTS narrator timer";
          Timer = {
            OnBootSec = "3min";
            OnUnitActiveSec = "3min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    arduino
    audacity
    edgetx
    firefox
    irssi
    kdePackages.kdenlive
    unstable.lmstudio
    unstable.obsidian
    prismlauncher
    pcsclite
    powertop
    saleae-logic-2
    spice
    #(mynix.NvidiaOffloadApp steam "steam")
    xclip
    xr-hardware
    yubikey-personalization
    
    mynix.cc-prism
    mynix.cura
    mynix.blhelisuite32
    mynix.rotorflight-blackbox
    mynix.rotorflight-configurator
    mynix.inav-configurator
    #(mynix.NvidiaOffloadApp mynix.HELI-X "HELI-X")
    mynix.HELI-X
    mynix.HELI-X11
  ];

  ###
  # Which unfree packages to allow
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "nvidia-x11"
    "nvidia-settings"
    "discord"
    "HELI-X"
    "joypixels"
    "libfprint-2-tod1-goodix-550a"
    "lmstudio"
    "resilio-sync"
    "saleae-logic-2"
    "steam"
    "steam-unwrapped"
    "obsidian"
    "claude-code"
  ];
  nixpkgs.config.joypixels.acceptLicense = true;

  # Derive ada's age key from SSH private key for sops decryption.
  # Runs after sops-nix decrypts the SSH key.
  systemd.services.ada-age-key = {
    description = "Derive ada's age key from SSH key";
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "ada-age-key" ''
        if [ -f /agents/ada/.ssh/id_ed25519 ]; then
          mkdir -p /agents/ada/.config/sops/age
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key \
            -i /agents/ada/.ssh/id_ed25519 \
            -o /agents/ada/.config/sops/age/keys.txt
          chown ada:ada /agents/ada/.config/sops/age/keys.txt
          chmod 600 /agents/ada/.config/sops/age/keys.txt
        fi
      '';
    };
  };

  # Seed: k3s + nix-snapshotter + Kata/CLH (VM-isolated pods)
  seed = {
    enable = true;
    k3s.port = 6444;
    persistence.enable = true;
    persistence.path = "/persist";
  };

  # ── Backup: external 4TB btrfs+LUKS drive ────────────────────
  # Auto-unlocks when plugged in using sops-decrypted key, then btrbk
  # snapshots @home and @persist to the backup drive.
  #
  # LUKS key is base64-encoded in sops — decode before use.
  systemd.services."unlock-backup" = {
    description = "Unlock external backup drive";
    requires = [ "dev-disk-by\\x2duuid-e7977738\\x2d6ffa\\x2d4b62\\x2d850c\\x2de8f744e6cb30.device" ];
    after = [
      "dev-disk-by\\x2duuid-e7977738\\x2d6ffa\\x2d4b62\\x2d850c\\x2de8f744e6cb30.device"
      "sops-install-secrets.service"
    ];
    wants = [ "sops-install-secrets.service" ];
    wantedBy = [ "dev-disk-by\\x2duuid-e7977738\\x2d6ffa\\x2d4b62\\x2d850c\\x2de8f744e6cb30.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "unlock-backup" ''
        if [ -e /dev/mapper/backup ]; then
          echo "backup already unlocked"
          exit 0
        fi
        ${pkgs.coreutils}/bin/base64 -d ${config.sops.secrets."backup/luks-key".path} | \
          ${pkgs.cryptsetup}/bin/cryptsetup open \
            /dev/disk/by-uuid/e7977738-6ffa-4b62-850c-e8f744e6cb30 \
            backup --key-file=-
      '';
      ExecStop = "${pkgs.cryptsetup}/bin/cryptsetup close backup";
    };
  };

  systemd.mounts = [{
    where = "/mnt/backup";
    what = "/dev/mapper/backup";
    type = "btrfs";
    options = "compress=zstd:3,noatime,nofail";
    bindsTo = [ "unlock-backup.service" ];
    after = [ "unlock-backup.service" ];
    wantedBy = [ "unlock-backup.service" ];
  }];

  services.btrbk.instances.backup = {
    onCalendar = "daily";
    settings = {
      snapshot_preserve_min = "2d";
      snapshot_preserve = "7d 4w 3m";
      target_preserve_min = "2d";
      target_preserve = "7d 4w 6m 1y";
      snapshot_dir = "_snapshots";
      volume."/home" = {
        target = "/mnt/backup/home";
        subvolume = ".";
      };
      volume."/persist" = {
        target = "/mnt/backup/persist";
        subvolume = ".";
      };
    };
  };

  system.stateVersion = "24.11";

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  #boot.blacklistedKernelModules = [ "nouveau" "nvidia" ];

  security.polkit.enable = true;
  security.soteria.enable = true; # polkit auth agent

  security.tpm2.enable = true;
  security.tpm2.pkcs11.enable = true;  # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
  security.tpm2.tctiEnvironment.enable = true;  # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables

  networking.hostName = "signi"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";
#  networking.networkmanager.wifi.powersave = true;
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.wifi.macAddress = "random";
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  networking.firewall.allowedUDPPorts = [
    # For networkmanager internet connection sharing dhcp dns
    53 67
    3333
    5353 # mDNS (systemd-resolved)
  ];
  networking.firewall.enable = true;

  # Set your time zone.
  time.timeZone = "America/Denver";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Decrypt sops age key via YubiKey GPG at boot (touch prompt on tty1)
  environment.etc."sops-age-key.gpg".source = ./age-key.txt.gpg;
  security.sops-age-yubikey = {
    enable = true;
    encryptedKeyFile = "/etc/sops-age-key.gpg";
    gpgPublicKey = ./josh-gpg-public.asc;
  };


  # Impermanence mappings
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/var/cache/nix"
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/fprint"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
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

  # Default umask 027: new files not world-readable for any user
  security.loginDefs.settings.UMASK = "027";

  users.users.josh = {
    uid = 1000;
    group = "josh";
    homeMode = "750";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [
      "wheel"     # Enable ‘sudo’ for the user.
      "plugdev"   # Access to usb devices
      "dialout"   # Access to serials ports
      "wireshark" # Access to packet capture
      "libvirtd"  # virtmanager
      "video"     # backlight et al
      "tss"       # TPM
    ];

    # Large subuid/subgid ranges (were needed for k3s rootless, keeping for podman)
    subUidRanges = [
      { startUid = 100000; count = 4294304; }
    ];
    subGidRanges = [
      { startGid = 100000; count = 4294304; }
    ];
  };

  users.groups.josh = {
   gid = 1000;
  };

  programs.steam.enable = true;
  hardware.steam-hardware.enable = true;

  programs.gnupg.agent = {
    enable = true;
    # SSH support handled per-user in home-manager (josh: gpg-agent, ada: ssh-agent)
  };

  programs.light = {
    enable = true;
    brightnessKeys.enable = true;
  };

  programs.thunar.plugins = with pkgs.xfce; [
    thunar-archive-plugin
    thunar-volman
  ];

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  programs.virt-manager = {
    enable = true;
  };

  ###
  # Hardware
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
    # Allow ada (and other local users) to play audio via PulseAudio TCP
    extraConfig.pipewire-pulse."30-tcp" = {
      "pulse.cmd" = [{
        cmd = "load-module";
        args = "module-native-protocol-tcp listen=127.0.0.1 auth-anonymous=1";
      }];
    };
  };

  # Power/Thermal management
  services.thermald.enable = true;

  # Fingerprint auth
  services.fprintd = {
    enable = true;
    tod = {
      enable = true;
      driver = pkgs.libfprint-2-tod1-goodix-550a;
    };
  };
  systemd.services.fprintd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "simple";
  };
  security.pam.lidCheck = {
      enable = true;
      services.swaylock.enable = false;
  };

  services.udev.packages = [
    # pkgs.mynix.stm-dfu-udev-rules  # Disabled: conflicts with ada setfacl rules below
    pkgs.qmk-udev-rules
  ];
  services.udev.extraRules = ''
    # LimeSuite
    SUBSYSTEM=="usb", ATTR{idVendor}=="04b4", ATTR{idProduct}=="8613", SYMLINK+="stream-%k", MODE="666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="04b4", ATTR{idProduct}=="00f1", SYMLINK+="stream-%k", MODE="666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="601f", SYMLINK+="stream-%k", MODE="666"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="6108", SYMLINK+="stream-%k", MODE="666"
    SUBSYSTEM=="xillybus", MODE="666"
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666"

  '';

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # OpenGL
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  hardware.saleae-logic = {
    enable = true;
  };

  #environment.sessionVariables = {
  #  LIBVA_DRIVER_NAME = "iHD";
  #};
  ## Modeset driver plz
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.finegrained = true;
    open = true;
    nvidiaSettings = true;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
    };
    package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
      version = "580.126.09";
      openSha256 = "sha256-ychsaurbQ2KNFr/SAprKI2tlvAigoKoFU1H7+SaxSrY=";
      settingsSha256 = "sha256-4SfCWp3swUp+x+4cuIZ7SA5H7/NoizqgPJ6S9fm90fA=";
      sha256_64bit = "sha256-TKxT5I+K3/Zh1HyHiO0kBZokjJ/YCYzq/QiKSYmG7CY=";
      sha256_aarch64 = "";
      persistencedSha256 = "";
    };
  };

  ###
  # Automatic display switching (EDID-based, GPU-mode agnostic)
  services.autorandr = let
    edid-laptop = "00ffffffffffff0030e488070000000000210104a5221678030f95ae5243b0260f505400000001010101010101010101010101010101353c80a070b023403020360059d71000001a2a3080a070b023403020360059d71000001a000000fe004d34573535803136305755340a0000000000024131b2001000000a410a20200088";
    edid-dell = "00ffffffffffff0010ac08434c37393202240104b55d27783bd9a5b04f3db1240e5054a54b00714f81008180a940b300d1c0d100e1c0d44600a0a0381f4030203a00a1883100001a000000ff0042374c4d3838340a2020202020000000fc0044454c4c20553430323551570a000000fd0c3078191996010a202020202020024502031ff152c17e7b6661605f5e5d101f04131211030201230907078301000050d000a0f0703e8030203500a1883100001a565e00a0a0a0295030203500a1883100001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094701279030001000c4d24500f001470081078899903013cf8120186ff139f002f801f006f083d000200090013440206ff137b01a38057006f0859000780090091870006ff139f002f801f006f081e0002000900000000000000000000000000000000000000000000000000000000000000000000000000000000000000004c90";

    # Build profiles for both Intel (eDP-1/DP-1) and NVIDIA sync (eDP-1-1/DP-1-1) output names
    mkProfiles = edp: dp: {
      "laptop${lib.optionalString (edp != "eDP-1") "-nv"}" = {
        fingerprint.${edp} = edid-laptop;
        config.${edp} = {
          enable = true;
          primary = true;
          mode = "1920x1200";
          position = "0x0";
          rate = "60.00";
        };
      };
      "docked${lib.optionalString (edp != "eDP-1") "-nv"}" = {
        fingerprint.${dp} = edid-dell;
        config.${dp} = {
          enable = true;
          primary = true;
          mode = "5120x2160";
          position = "0x0";
          rate = "60.00";
        };
      };
      "docked-open${lib.optionalString (edp != "eDP-1") "-nv"}" = {
        fingerprint.${edp} = edid-laptop;
        fingerprint.${dp} = edid-dell;
        config.${edp}.enable = false;
        config.${dp} = {
          enable = true;
          primary = true;
          mode = "5120x2160";
          position = "0x0";
          rate = "60.00";
        };
      };
      "dual${lib.optionalString (edp != "eDP-1") "-nv"}" = {
        fingerprint.${edp} = edid-laptop;
        fingerprint.${dp} = edid-dell;
        config.${dp} = {
          enable = true;
          primary = true;
          mode = "5120x2160";
          position = "0x0";
          rate = "60.00";
        };
        config.${edp} = {
          enable = true;
          mode = "1920x1200";
          position = "5120x480";
          rate = "60.00";
        };
      };
    };
  in {
    enable = true;
    matchEdid = true;
    defaultTarget = "laptop";

    profiles =
      (mkProfiles "eDP-1" "DP-1") //
      (mkProfiles "eDP-1-1" "DP-1-1");

    # Switch profile on lid open/close (not just display hotplug)
    hooks.postswitch = {
      "notify" = "echo 'autorandr: switched to $AUTORANDR_CURRENT_PROFILE'";
    };
  };

  # Lid listener — autorandr's udev hook only fires on display hotplug,
  # not lid events. This watches libinput for SWITCH_TOGGLE (lid) and
  # triggers autorandr --change.
  systemd.services.autorandr-lid-listener = {
    description = "Autorandr lid listener";
    wantedBy = [ "multi-user.target" ];
    after = [ "display-manager.service" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 30;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/stdbuf -oL ${pkgs.libinput}/bin/libinput debug-events | ${pkgs.gnugrep}/bin/grep -E --line-buffered \"^[[:space:]-]+event[0-9]+[[:space:]]+SWITCH_TOGGLE[[:space:]]\" | while read line; do ${pkgs.autorandr}/bin/autorandr --batch --change --default laptop; done'";
    };
  };

  ###
  # X11 windowing system.
  services.xserver = {
    enable = true;

    videoDrivers = [ "nvidia" ];

    dpi = 96;

    desktopManager = {
      runXdgAutostartIfNone = true;
      xterm.enable = false;
    };

    displayManager = {
      setupCommands = ''
        ${pkgs.autorandr}/bin/autorandr --change --default laptop
      '';
    };

    xkb = {
      # map caps to escape.
      options = "caps:escape";
    };

    windowManager.i3 = {
      enable = true;
      package = pkgs.i3;
      extraPackages = [ ];
    };
  };

  services.displayManager = {
    defaultSession = "none+i3";
  };

  xdg.portal = {
    enable = true;
    config = {
      common = {
        default = [ "lxqt" ];
      };
    };
    extraPortals = with pkgs; [
      lxqt.xdg-desktop-portal-lxqt
    ];
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      powerline-symbols
      joypixels
      inconsolata
      font-awesome
      nerd-fonts.sauce-code-pro
    ];
    fontconfig = {
      antialias = true;
      cache32Bit = true;
      hinting.enable = true;
      hinting.autohint = true;
      defaultFonts = {
        monospace = [ "SauceCodePro Nerd Font Mono Regular" ];
      };
    };
  };

  specialisation = {
    nvidia-primary.configuration = {
      environment.sessionVariables = {
        VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
        VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
        NODEVICE_SELECT = "1"; 
      };

      hardware.nvidia = {
        powerManagement.finegrained = lib.mkForce false;
        powerManagement.enable = true;
        prime = {
          sync.enable = true;
          offload = {
            enable = lib.mkForce false;
            enableOffloadCmd = lib.mkForce false;
          };
        };
      };

      # defaultTarget needs to match the nvidia profile name
      services.autorandr.defaultTarget = lib.mkForce "laptop-nv";
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;

  ###
  # SERVICES
  virtualisation = {
    containers.enable = true;

    libvirtd = {
      enable = true;
    };

    spiceUSBRedirection.enable = true;

    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # smartcard
  services.pcscd.enable = true;
  # Thunar services
  services.gvfs.enable = true;
  services.tumbler.enable = true; 

  services.printing = {
    enable = true;
  };

  # iDevice comms
  #services.usbmuxd.enable = true;

  # Resilio Sync
#  services.resilio = {
#    enable = true;
#    checkForUpdates = false;
#    directoryRoot = "/mnt/guiltyspark/sync";
#    storagePath = "/mnt/guiltyspark/sync/db";
#    enableWebUI = true;
#    httpListenAddr = "127.0.0.1";
#    httpLogin = "admin";
#    httpPass = "admin1234";
#    listeningPort = 55555;
#    useUpnp = false;
#  };

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # systemd-resolved handles DNS + mDNS resolution (replaces nss-mdns)
  services.resolved = {
    enable = true;
    #dnssec = "allow-downgrade";
    extraConfig = "MulticastDNS=yes";
  };

  # Avahi disabled — systemd-resolved handles mDNS resolution + hostname publishing
  services.avahi.enable = false;

  services.fwupd.enable = true;

  services.kubo = {
    enable = false;
  };

  ###
  # Users
  users.mutableUsers = false;

  users.users.root = {
    hashedPassword = "!"; # Disable the root password
  };

  users.groups.plugdev = {
  };
})
