({ pkgs, config, ... }:
{
  imports = [
    ../../profiles/graphical.nix
  ];

  system.stateVersion = "23.11";

  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };

  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "${config.users.users.josh.home}/dev/mynix";
    flags = [
      "--update-input" "nixpkgs"
    ];
  };

  environment.systemPackages = with pkgs; [
    docker-compose
    pcsclite
    xclip
    yubikey-personalization
    slack
    google-chrome
    (google-cloud-sdk.withExtraComponents [google-cloud-sdk.components.gke-gcloud-auth-plugin])
    kubectl
    k9s
    irssi
    proxmark3-rrg
    inkscape
    _1password-gui
    _1password
    firefox
    asciinema

    # Install xss-lock branch that comms with logind for lock-on-sleep
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
      "dialout"   # Access to serial devices
      "video"     # Access to video devices
      "wireshark" # Access to packet capture
      "docker"    # Containerize all the things
    ];
  };

  users.groups.josh = {
   gid = 1000;
  };

  ###
  # Which unfree packages to allow
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "discord"
    "drata"
    "falcon-sensor"
    "google-chrome"
    "nvidia-x11"
    "nvidia-settings"
    "slack"
    "1password"
    "1password-cli"
  ];

  virtualisation.docker.enable = true;

  programs.drata.enable = true;
  programs.falcon.enable = true;

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

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security.polkit.enable = true;

  security.pam.loginLimits = [{
    domain = "*";
    type = "soft";
    item = "nofile";
    value = "65536";
  }];

  networking.hostName = "xeeps"; # Define your hostname.
  networking.networkmanager.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.enable = true;

  # Set your time zone.
  time.timeZone = "MST7MDT";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  ###
  # Hardware
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  #hardware.opengl.enable = true;

  programs.light.enable = true;

  ###
  # X11 windowing system.
  services.xserver = {
    enable = true;

    #videoDrivers = [ "nvidia" ];

    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      defaultSession = "none+i3";
      setupCommands = ''
        ${pkgs.xorg.xrandr}/bin/xrandr --output eDP-1 --mode 1920x1200
      '';
      # Configure the greeter to use the primary monitor
      # xrandr `primary` isn't respected, and old tech like DVI tends to get priority
      lightdm.greeters.gtk.extraConfig = ''
        active-monitor=0
      '';
    };

    # map caps to escape.
    xkbOptions = "caps:escape";

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

  # smartcard
  services.pcscd.enable = true;
  # Thunar services
  services.gvfs.enable = true;
  services.tumbler.enable = true; 

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  services.avahi = {
    enable = true;
    nssmdns = true;
    openFirewall = true;
    domainName = "local";
    publish = {
      enable = true;
      domain = true;
      addresses = true;
      workstation = true;
    };
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
