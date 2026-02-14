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
    flameshot
    playerctl
    mynix.i3lock-color
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

  xsession.windowManager.i3 = {
    enable = true;
    package = pkgs.i3;

    config = let
      modifier = "Mod4";
    in {
      inherit modifier;

      fonts = {
        names = [ "Source Code Pro for Powerline" ];
        size = 10.0;
      };

      floating.modifier = modifier;

      terminal = "i3-sensible-terminal";

      keybindings = let
        mod = modifier;
      in {
        # Terminal and browser
        "${mod}+Return" = "exec i3-sensible-terminal";
        "${mod}+Shift+Return" = "exec ${lib.getExe pkgs.ungoogled-chromium}";

        # Kill focused window
        "${mod}+Shift+q" = "kill";

        # Rofi launcher
        "${mod}+space" = ''exec --no-startup-id "rofi -combi-modi window,drun,ssh -show combi"'';

        # Lock screen
        "${mod}+F12" = "exec --no-startup-id xset s activate";

        # Vim-style focus
        "${mod}+h" = "focus left";
        "${mod}+j" = "focus down";
        "${mod}+k" = "focus up";
        "${mod}+l" = "focus right";

        # Arrow key focus
        "${mod}+Left" = "focus left";
        "${mod}+Down" = "focus down";
        "${mod}+Up" = "focus up";
        "${mod}+Right" = "focus right";

        # Vim-style move
        "${mod}+Shift+h" = "move left";
        "${mod}+Shift+j" = "move down";
        "${mod}+Shift+k" = "move up";
        "${mod}+Shift+l" = "move right";

        # Arrow key move
        "${mod}+Shift+Left" = "move left";
        "${mod}+Shift+Down" = "move down";
        "${mod}+Shift+Up" = "move up";
        "${mod}+Shift+Right" = "move right";

        # Split
        "${mod}+bar" = "split h";
        "${mod}+minus" = "split v";

        # Layout
        "${mod}+f" = "fullscreen toggle";
        "${mod}+s" = "layout stacking";
        "${mod}+w" = "layout tabbed";
        "${mod}+e" = "layout toggle split";

        # Floating
        "${mod}+Shift+space" = "floating toggle";

        # Focus parent
        "${mod}+a" = "focus parent";

        # Workspaces
        "${mod}+1" = "workspace 1";
        "${mod}+2" = "workspace 2";
        "${mod}+3" = "workspace 3";
        "${mod}+4" = "workspace 4";
        "${mod}+5" = "workspace 5";
        "${mod}+6" = "workspace 6";
        "${mod}+7" = "workspace 7";
        "${mod}+8" = "workspace 8";
        "${mod}+9" = "workspace 9";
        "${mod}+0" = "workspace 10";

        "${mod}+Shift+1" = "move container to workspace 1";
        "${mod}+Shift+2" = "move container to workspace 2";
        "${mod}+Shift+3" = "move container to workspace 3";
        "${mod}+Shift+4" = "move container to workspace 4";
        "${mod}+Shift+5" = "move container to workspace 5";
        "${mod}+Shift+6" = "move container to workspace 6";
        "${mod}+Shift+7" = "move container to workspace 7";
        "${mod}+Shift+8" = "move container to workspace 8";
        "${mod}+Shift+9" = "move container to workspace 9";
        "${mod}+Shift+0" = "move container to workspace 10";

        # i3 management
        "${mod}+Shift+c" = "reload";
        "${mod}+Shift+r" = "restart";
        "${mod}+Shift+e" = ''exec "i3-nagbar -t warning -m 'You pressed the exit shortcut. Do you really want to exit i3? This will end your X session.' -b 'Yes, exit i3' 'i3-msg exit'"'';

        # Modes
        "${mod}+r" = ''mode "resize"'';
        "${mod}+Shift+s" = ''mode "display"'';

        # Move workspace between monitors
        "${mod}+Ctrl+l" = "move workspace to output right";
        "${mod}+Ctrl+h" = "move workspace to output left";

        # Flameshot
        "Print" = "exec ${lib.getExe pkgs.flameshot} gui";
        "${mod}+Print" = "exec ${lib.getExe pkgs.flameshot} full -c";
        "${mod}+Shift+Print" = "exec ${lib.getExe pkgs.flameshot} full -p /tmp/";

        # Gutter toggle
        "${mod}+z" = "exec ~/.local/bin/i3gutter";
        "${mod}+x" = "nop";

        # Media volume (wireplumber)
        "XF86AudioRaiseVolume" = "exec --no-startup-id ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ && killall -SIGUSR1 i3status";
        "XF86AudioLowerVolume" = "exec --no-startup-id ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%- && killall -SIGUSR1 i3status";
        "XF86AudioMute" = "exec --no-startup-id ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && killall -SIGUSR1 i3status";
        "XF86AudioMicMute" = "exec --no-startup-id ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && killall -SIGUSR1 i3status";

        # Media playback
        "XF86AudioNext" = "exec ${lib.getExe pkgs.playerctl} next";
        "XF86AudioPrev" = "exec ${lib.getExe pkgs.playerctl} previous";
        "XF86AudioPlay" = "exec ${lib.getExe pkgs.playerctl} play-pause";
        "XF86AudioStop" = "exec ${lib.getExe pkgs.playerctl} stop";
      };

      modes = {
        resize = {
          "h" = "resize shrink width 10 px or 10 ppt";
          "j" = "resize grow height 10 px or 10 ppt";
          "k" = "resize shrink height 10 px or 10 ppt";
          "l" = "resize grow width 10 px or 10 ppt";
          "Left" = "resize shrink width 10 px or 10 ppt";
          "Down" = "resize grow height 10 px or 10 ppt";
          "Up" = "resize shrink height 10 px or 10 ppt";
          "Right" = "resize grow width 10 px or 10 ppt";
          "Return" = ''mode "default"'';
          "Escape" = ''mode "default"'';
          "${modifier}+r" = ''mode "default"'';
        };

        display = {
          "i" = ''exec "~/.screenlayout/screen-laptop.sh" mode "default"'';
          "o" = ''exec "~/.screenlayout/screen-office.sh" mode "default"'';
          "h" = ''exec "~/.screenlayout/screen-home.sh" mode "default"'';
          "e" = ''exec "~/.screenlayout/screen-projector-extend.sh" mode "default"'';
          "m" = ''exec "~/.screenlayout/screen-projector-mirror.sh" mode "default"'';
          "Return" = ''mode "default"'';
          "Escape" = ''mode "default"'';
        };
      };

      bars = [{
        statusCommand = "${lib.getExe pkgs.i3status}";
        trayOutput = "primary";
      }];

      window.commands = [
        { command = "floating enable"; criteria = { class = "zoom"; }; }
        { command = "floating disable"; criteria = { class = "zoom"; title = "Zoom Meeting"; }; }
      ];

      startup = [
        { command = "${lib.getExe pkgs.dunst}"; notification = false; }
        { command = "${pkgs.networkmanagerapplet}/bin/nm-applet"; notification = false; }
        { command = "${lib.getExe pkgs.pasystray}"; notification = false; }
        { command = "${lib.getExe pkgs.mynix.xss-lock-hinted} --transfer-sleep-lock -- session-lock"; always = true; notification = false; }
      ];

      gaps = {
        inner = 10;
        outer = 0;
        smartGaps = true;
      };
    };
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
