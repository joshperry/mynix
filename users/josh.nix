{ config, pkgs, ... }: {
  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    audacity
    unstable.blender
    discord
    fzf
    git
    unstable.gitmux
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
    tmux
    tmuxinator
    terminator
    ungoogled-chromium
    xfce.thunar
  ];

  programs.bash = {
    enable = true;

    shellAliases = {
      ll = "ls --color=auto";
    };

    sessionVariables = {
      EDITOR = "vim";
    };

    initExtra = ''
      stty susp undef
      bind -x '"\C-z":"fg"'

      function _update_ps1() {
        PS1="$(powerline-go -modules 'venv,user,ssh,cwd,perms,git,jobs,exit,root,nix-shell' -error $?)"
      }
      PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"

      set -o vi
      gpgconf --launch gpg-agent
    '';
  };
}
