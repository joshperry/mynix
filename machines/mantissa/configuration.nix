({ pkgs, ... }: {
  imports = [
    ../../profiles/graphical.nix
  ];

  system.stateVersion = "23.11";

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.blacklistedKernelModules = [ "nouveau" "nvidia" ];

  security.polkit.enable = true;

  networking.hostName = "mantissa"; # Define your hostname.
  networking.networkmanager.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.enable = true;

  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    firefox
    irssi
    light
    pcsclite
    spice
    saleae-logic-2
    xclip
    yubikey-personalization
    xss-lock-hinted
  ];

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

  ###
  # Which unfree packages to allow
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "discord"
    "resilio-sync"
    "saleae-logic"
  ];

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

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
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
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

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

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };
  ## Modeset driver plz
  #hardware.nvidia.modesetting.enable = true;

  ###
  # X11 windowing system.
  services.xserver = {
    enable = true;

    videoDrivers = [ "modesetting" ];

    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      setupCommands = ''
        ${pkgs.xorg.xrandr}/bin/xrandr --output eDP-1 --mode 1920x1080 --pos 0x0 --rotate normal --primary
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
        i3lock-color
        i3blocks
      ];
    };
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      powerline-symbols
      emojione
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

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;

  ###
  # SERVICES
  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
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

  services.kubo = {
    enable = true;
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
