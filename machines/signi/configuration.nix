({ pkgs, config, ... }: {
  imports = [
    ./hardware-configuration.nix
    ../../profiles/graphical.nix
  ];

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
    
    mynix.itunes-backup-explorer
    mynix.blhelisuite32
    mynix.rotorflight-blackbox
    mynix.rotorflight-configurator
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

  networking.hostName = "signi"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.wifi.macAddress = "random";
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.enable = true;

  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

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

  users.users.josh = {
    uid = 1000;
    group = "josh";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [
      "wheel"     # Enable ‘sudo’ for the user.
      "plugdev"   # Access to usb devices
      "dialout"   # Access to serials ports
      "wireshark" # Access to packet capture
      "libvirtd"  # virtmanager
      "video"     # backlight et al
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

  services.udev.packages = [ 
    pkgs.mynix.stm-dfu-udev-rules
    pkgs.android-udev-rules
  ];

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # OpenGL
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
      vaapiIntel
      vaapiVdpau
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
      version = "580.95.05";
      openSha256 = "sha256-RFwDGQOi9jVngVONCOB5m/IYKZIeGEle7h0+0yGnBEI=";
      settingsSha256 = "sha256-F2wmUEaRrpR1Vz0TQSwVK4Fv13f3J9NJLtBe4UP2f14=";
      sha256_64bit = "sha256-hJ7w746EK5gGss3p8RwTA9VPGpp2lGfk5dlhsv4Rgqc=";
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
      ];
    };
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
  systemd = {
  };

  virtualisation = {
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

  services.displayManager = {
    defaultSession = "none+i3";
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
