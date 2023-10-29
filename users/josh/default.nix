{ config, pkgs, lib, ... }: {
  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    audacity
    unstable.blender
    darktable
    discord
    fzf
    gimp-with-plugins
    gitmux
    unstable.godot_4
    imagemagick
    libcanberra-gtk3
    networkmanagerapplet
    obs-studio
    pasystray
    pavucontrol
    paprefs
    powerline
    powerline-go
    scrot
    silver-searcher
    thunderbird
    tmuxinator
    terminator
    ungoogled-chromium
    vlc
    xfce.thunar
  ];

  programs.rofi = {
    enable = true;
    font = "SauceCodePro Nerd Font Mono Regular";
    terminal = "${pkgs.terminator}/bin/terminator";
    theme = "gruvbox-dark-hard";
    plugins = with pkgs; [
      rofi-file-browser
      rofi-power-menu
      rofi-pulse-select
      rofi-systemd
      rofi-top
    ];
    extraConfig = {
      modi = "window,run,ssh,combi,drun";
      combi-modi = "window,drun";
      ssh-command = "{terminal} -e '{ssh-client} {host} [-p {port}]'";
    };
  };

  home.file.".local/bin/dev" = {
    source = ./scripts/dev.sh;
    executable = true;
  };

  programs.git = {
    enable = true;
    userName = "Joshua Perry";
    userEmail = lib.mkDefault "josh@6bit.com";
    #signing = {
    #  key = null;
    #  signByDefault = true;
    #};
    extraConfig = {
      commit.gpgSign = true;
      tag.gpgSign = true;
      init.defaultBranch = "master";
      pull.rebase = true;
    };
  };

  programs.tmux = {
    enable = true;
    extraConfig = lib.fileContents config/tmux/tmux.conf;
    plugins = [
      pkgs.tmuxPlugins.tmux-fzf
    ];
  };

  programs.neovim = {
    enable = true;
    extraConfig = ''
      set number relativenumber
    '';
  };

  programs.direnv = { # <-- me succumbing to direnv
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
  };

  programs.bash = {
    enable = true;

    shellAliases = {
      ll = "ls --color=auto";
      pbcopy = "xclip -sel clip"; # I used macs for a decade
      pbpaste = "xclip -o";
      cdf = "cd $(find . -maxdepth 2 -type d -print | fzf)"; # Don't use this much with `dev` alias
      tdie = "tmux killw";
      ndi = "nix develop --impure"; # <-- me avoiding direnv
    };

    sessionVariables = {
      EDITOR = "nvim";
    };

    initExtra = ''
      PATH=/home/josh/.local/bin:$PATH
      stty susp undef
      bind -x '"\C-z":"fg"'

      function _update_ps1() {
        PS1="$(powerline-go -modules 'venv,ssh,cwd,perms,git,jobs,exit,root,nix-shell' -error $?)"
      }
      PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"

      set -o vi
      gpgconf --launch gpg-agent
    '';
  };
}
