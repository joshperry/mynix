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
  };

  # ── Nuketown: AI agent framework ──────────────────────────────
  nuketown = {
    enable = true;
    domain = "signi.local";
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
        ".config/claude"
      ];

      sudo.enable = true;
      portal.enable = true;

      secrets.sshKey = "ada/ssh-key";
      secrets.gpgKey = "ada/gpg-key";
      secrets.extraSecrets.email-password = "ada/email-password";

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
      ];

      claudeCode = {
        enable = true;
        settings = {
          env = {
            CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
          };
          permissions = {
            defaultMode = "bypassPermissions";
            additionalDirectories = [
              "/home/josh/dev"
            ];
          };
        };
        extraPrompt = ''
          ## Working Style

          - Read the project's CLAUDE.md before starting work
          - Prefer editing existing files over creating new ones
          - You cannot use interactive commands (no TTY)

          ## NixOS Workflow

          To build and apply system configuration changes:
          1. `nixos-rebuild build --flake . --show-trace`
          2. `nvd diff /run/current-system result`
          3. `sudo sh -c 'nix-env -p /nix/var/nix/profiles/system --set ./result && ./result/bin/switch-to-configuration switch'`
          4. `unlink result`
        '';
      };

      extraHomeConfig = {
        home.stateVersion = "25.11";
        programs.gpg.enable = true;
        programs.git.signing.key = "6CD1AEABA566EC82";
        # Import GPG key from sops secret on login
        programs.bash.profileExtra = ''
          if [ -f ${config.sops.secrets."ada/gpg-key".path} ]; then
            gpg --batch --import ${config.sops.secrets."ada/gpg-key".path} 2>/dev/null || true
          fi
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
      };
    };
  };

  environment.systemPackages = with pkgs; [
    arduino
    edgetx
    firefox
    irssi
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
    
    mynix.blhelisuite32
    mynix.rotorflight-blackbox
    mynix.rotorflight-configurator
    mynix.inav-configurator
    mynix.xss-lock-hinted
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

  #nixpkgs.overlays = [
  #  (final: prev: {
  #    steam = prev.steam.override {
  #      extraPkgs = pkgs': with pkgs'; [
  #        qt5.qtbase
  #        audit
  #        libsForQt5.qt5.qtmultimedia
  #      ];
  #    };
  #  })
  #];

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
#  networking.networkmanager.wifi.powersave = true;
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.wifi.macAddress = "random";
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  networking.firewall.allowedUDPPorts = [
    # For networkmanager internet connection sharing dhcp dns
    53 67 
    3333
  ];
  networking.firewall.enable = true;

  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # GPG-encrypted age key — placed by nix, decrypted at runtime via broker
  environment.etc."sops-age-key.gpg".source = ./age-key.txt.gpg;


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

    # Add large subuid/subgid ranges for k3s
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
    enableSSHSupport = true;
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
        ${pkgs.xorg.xrandr}/bin/xrandr --output eDP-1 --mode 1920x1200 --pos 0x0 --rotate normal --primary
      '';
    };

    xkb = {
      # map caps to escape.
      options = "caps:escape";
    };

    windowManager.i3 = {
      enable = true;
      package = pkgs.i3;
      extraPackages = with pkgs; [
        dmenu
        dunst
        i3status
        i3lock
        mynix.i3lock-color
        i3blocks
        wireplumber
      ];
    };
  };

  services.displayManager = {
    defaultSession = "none+i3";
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

      services.xserver.displayManager.setupCommands = lib.mkForce ''
        ${pkgs.xorg.xrandr}/bin/xrandr --output eDP-1-1 --mode 1920x1200 --pos 0x0 --rotate normal --primary
      '';
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

  services.k3s.rootless.enable = true;

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

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    domainName = "local";
    publish = {
      enable = true;
      domain = true;
      addresses = true;
      workstation = true;
    };
  };

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
