{ pkgs, lib, ... }: {
  imports = [
    ./cli.nix
  ];

  home.stateVersion = "23.11";

  systemd.user.startServices = "sd-switch";

  home.packages = with pkgs; [
    # My scripts
    (import ./scripts/dev.nix { inherit pkgs; })
    (writeShellScriptBin "i3gutter" (lib.fileContents scripts/i3gutter.sh))
    (writeShellScriptBin "session-lock" (lib.fileContents config/i3/scripts/session-lock.sh))

    #(writeShellScriptBin "session-lock" ''
    #  ${./config/i3/scripts/session-lock.sh} ${./config/i3/scripts/lockscreen.gif}
    #'')

    audacity
    unstable.blender
    darktable
    discord
    gimp-with-plugins
    libcanberra-gtk3
    nerdctl
    networkmanagerapplet
    obs-studio
    pasystray
    pavucontrol
    paprefs
    scrot
    thunderbird
    ungoogled-chromium
    vlc
    xfce.thunar
    unstable.godot
  ];

  # One thing I learned this week: the coolest things ghostty does is when it acts as a subset of kitty
  programs.kitty = {
    enable = true;
    themeFile = "gruvbox-dark";
    font = {
      name = "Source Code Pro for Powerline Regular";
      size = 11;
    };
    settings = {
      enable_audio_bell = false;
      update_check_interval = 0;
      adjust_line_height = "120%";
    };
  };

  programs.rofi = {
    enable = true;
    font = "SauceCodePro Nerd Font Mono Bold 12";
    terminal = lib.getExe pkgs.kitty;
    theme = "gruvbox-dark-hard";
    plugins = with pkgs; [
      rofi-file-browser
      rofi-power-menu
      rofi-pulse-select
      rofi-systemd
      rofi-top
      rofi-obsidian
    ];
    extraConfig = {
      modi = "window,run,ssh,combi,drun";
      combi-modi = "window,drun";
      ssh-command = "{terminal} -e '{ssh-client} {host} [-p {port}]'";
    };
  };

  home.file.".config/i3/config" = {
    source = ./config/i3/config;
  };

  virtualisation.containerd.rootless = {
    enable = true;
    nixSnapshotterIntegration = true;
  };

  services.nix-snapshotter.rootless = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Desktop-specific bash additions
  programs.bash.shellAliases = {
    pbcopy = "xclip -sel clip"; # I used macs for a decade
    pbpaste = "xclip -o";
  };

  programs.bash.sessionVariables = {
    TERMINAL = "kitty"; 
  };
}
