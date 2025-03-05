({ pkgs, ... }: {
  imports = [
    ../../profiles/common.nix
  ];

  system.stateVersion = "23.11";

  environment.systemPackages = with pkgs; [
    arduino
    firefox
    inkscape
    aseprite
    irssi
    signal-desktop
    pcsclite
    xclip
    yubikey-personalization
    unstable.k3d
    cura
    visidata

    # Install xss-lock branch that comms with logind
    # https://chat.openai.com/c/6f543d75-9dbb-4b0c-8188-08152032821a
    (xss-lock.overrideAttrs (_: {
      src = fetchFromGitHub {
        owner = "xdbob";
        repo = "xss-lock";
        rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
        sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
      };
    }))
  ];

  users.users.josh = {
    uid = 1000;
    group = "josh";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [
      "wheel"     # Enable ‘sudo’ for the user.
      "plugdev"   # Access to usb devices
      "input"     # USB device input
      "dialout"   # Access serial ports
      "wireshark" # Access to packet capture
    ];
  };

  users.groups.josh = {
   gid = 1000;
  };

  ###
  # Which unfree packages to allow
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "aseprite"
    "discord"
    "nvidia-x11"
    "nvidia-settings"
    "steam"
    "steam-original"
    "steam-run"
    "steam-unwrapped"
    "resilio-sync"
    "plexamp-4.8.3"
  ];

  nixpkgs.overlays = [
    (final: prev: {
      xdg-desktop-portal = prev.xdg-desktop-portal.override {
        enableGeoLocation = false;
      };
    })
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.steam = {
    enable = true;
  };

  programs.thunar.plugins = with pkgs.xfce; [
    thunar-archive-plugin
    thunar-volman
  ];

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security.polkit.enable = true;

  networking.hostName = "bones"; # Define your hostname.
  networking.networkmanager.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.enable = true;

  networking.firewall.allowedTCPPorts = [ 21 ];
  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  ###
  # Hardware
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  services.printing = {
    enable = true;
    drivers = [
      pkgs.hplip
    ];
  };
  hardware.printers = {
    ensurePrinters = [
      {
        name = "HP-P2015";
        location = "Home";
        deviceUri = "usb://HP/LaserJet%20P2015%20Series?serial=00CNB1R45127";
        model = "HP/hp-laserjet_p2015_series-pcl3.ppd.gz";
      }
    ];
  };

  # Video card driver
  hardware.nvidia = {
    open = false;
    modesetting.enable = true;
  };

  # OpenGL
  hardware.graphics = {
    enable = true;
    extraPackages = [
      pkgs.nvidia-vaapi-driver
      pkgs.vaapiVdpau
      pkgs.libvdpau-va-gl
    ];
  };

  ###
  # X11 windowing system.
  services.xserver = {
    enable = true;

    videoDrivers = [ "nvidia" ];

    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      setupCommands = ''
        ${pkgs.xorg.xrandr}/bin/xrandr --output DVI-D-0 --mode 2560x1600 --pos 3840x0 --rotate left --output HDMI-0 --off --output DP-0 --off --output DP-1 --off --output DP-2 --primary --mode 3840x1600 --pos 0x960 --rotate normal --output DP-3 --off --output DP-4 --off --output DP-5 --off
      '';
      # Configure the greeter to use the primary monitor
      # xrandr `primary` isn't respected, and old tech like DVI tends to get priority
      lightdm.greeters.gtk.extraConfig = ''
        active-monitor=0
      '';
    };

    # map caps to escape.
    xkb.options = "caps:escape";

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

  services.displayManager = {
    defaultSession = "none+i3";
  };

  xdg.portal = {
    enable = true;
    config = {
      common = {
        default = [ "xfce" ];
      };
    };
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      powerline-symbols
      emojione
      inconsolata
      font-awesome
      (nerdfonts.override { fonts = [
        "SourceCodePro"
      ];})
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
  services.resilio = {
    enable = true;
    checkForUpdates = false;
    directoryRoot = "/mnt/guiltyspark/sync";
    storagePath = "/mnt/guiltyspark/sync/db";
    enableWebUI = true;
    httpListenAddr = "127.0.0.1";
    httpLogin = "admin";
    httpPass = "admin1234";
    listeningPort = 55555;
    useUpnp = false;
  };

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


  ## FTP Setup

  # User for camera FTP uploads
  users.users.janus = {
    group = "josh";
    home = "/mnt/kago/pic/camftp";
    initialHashedPassword = "$6$rounds=1000$M3h5rHnoZ8NVtllY$Sa4PhtobRQA6.wn7tvJoYdPo06kGc9vgdcCT0Wtbpt20RB3A6Ck7C.5g8d1F1X1.kYw.3RXaPXkHXeP6X0Afz.";
    isSystemUser = true;
  };

  networking.firewall.allowedTCPPortRanges = [
    # vsftpd pasv ports
    { from = 51000; to = 51009; }
  ];

  services.vsftpd = {
    enable = true;
    localUsers = true;
    chrootlocalUser = true;
    writeEnable = true;
    allowWriteableChroot = true;
    userlistEnable = true;
    userlist = [
      "janus"
    ];
    extraConfig = ''
      cmds_denied=DELE,RMD,MKD,RNTO,RNFR
      delete_failed_uploads=YES
      download_enable=NO
      hide_ids=YES
      log_ftp_protocol=YES
      pasv_min_port=51000
      pasv_max_port=51009
    '';
  };

  services.udev.packages = [ 
    # QMK keyboards
    pkgs.qmk-udev-rules
  ];

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
