{ pkgs, lib, ... }: {
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    audacity
    bat
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
    terminator
    ungoogled-chromium
    vlc
    xfce.thunar
  ];

  programs.kitty = {
    enable = true;
    theme = "Gruvbox Dark";
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
    userName = lib.mkDefault "Joshua Perry";
    userEmail = lib.mkDefault "josh@6bit.com";
    signing = lib.mkDefault {
      key = null;
      signByDefault = true;
    };
    extraConfig = {
      init.defaultBranch = "master";
      pull.rebase = true;
      rebase.autostash = true;
    };
  };

  programs.tmux = {
    enable = true;
    extraConfig = lib.fileContents config/tmux/tmux.conf;
    shortcut = "a";
    terminal = "tmux-256color";
    historyLimit = 20000;
    mouse = true;
    keyMode = "vi";
    escapeTime = 0; # no esc delay, for vim
    tmuxinator.enable = true;
    plugins = [
      pkgs.tmuxPlugins.tmux-fzf
    ];
  };

  programs.neovim = { # the power of lua beckons
    enable = true;
    extraConfig = lib.fileContents config/vim/vimrc;
    coc ={ # universal lsp client
      enable = true;
      settings = {
        "suggest.noselect" = true;
        "suggest.enablePreview" = true;
        "suggest.enablePreselect" = false;
        "suggest.disableKind" = true;
        languageserver.nix = { # nix language server
          command = "${pkgs.nil}/bin/nil";
          filetypes = ["nix"];
          rootPatterns = ["flake.nix"];
        };
      };
    };
    plugins = with pkgs.vimPlugins; [
      nvim-web-devicons
      gruvbox      # theme
      coc-eslint   # CoC lsps
      coc-go
      coc-tsserver
      coc-yaml
      coc-rust-analyzer
      vim-tmux-navigator # allow ctrl-hjkl across panes
      vim-polyglot       # syntax highlight all the things
      mini-nvim          #TODO: Still unsure how to use mini.file from this, supercede oil?
      vim-fugitive       # Git interaction
      vimwiki            # Wiki notes in vim
      fzf-vim            # file path/contents fuzzyfind
      pkgs.unstable.vimPlugins.openingh-nvim
      {
        plugin = neo-tree-nvim;
        type = "lua";
        config = ''
          require('neo-tree').setup({
            filesystem = {
              use_libuv_file_watcher = true,
            },
          })
        '';
      }
      {
        plugin = gitsigns-nvim; # git gutter and interaction
        type = "lua";
        config = "require('gitsigns').setup()";
      }
      {
        plugin = lualine-nvim; #powerline-alike
        type = "lua";
        config = "require('lualine').setup()";
      }
      {
        plugin = oil-nvim; # netrw replacement
        type = "lua";
        config = "require('oil').setup()";
      }
    ];
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
      TERMINAL = "kitty";
    };

    initExtra = ''
      PATH=/home/josh/.local/bin:$PATH
      stty susp undef
      bind -x '"\C-z":"fg"'

      function _update_ps1() {
        PS1="$(${pkgs.powerline-go}/bin/powerline-go -modules 'venv,ssh,cwd,perms,git,jobs,exit,root,nix-shell' -error $?)"
      }
      PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"

      set -o vi
      gpgconf --launch gpg-agent
    '';
  };
}
