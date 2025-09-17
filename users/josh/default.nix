{ pkgs, lib, ... }: {
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    # My scripts
    (writeShellScriptBin "dev" (lib.fileContents scripts/dev.sh))
    (writeShellScriptBin "i3gutter" (lib.fileContents scripts/i3gutter.sh))
    (writeShellScriptBin "session-lock" (lib.fileContents config/i3/scripts/session-lock.sh))

    audacity
    bat
    unstable.blender
    darktable
    discord
    fzf
    gimp-with-plugins
    gitmux
    unstable.godot
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

  home.file.".config/powerline/themes/tmux/default.json" = {
    source = ./config/powerline/tmux/default.json;
  };

  home.file.".config/i3/config" = {
    source = ./config/i3/config;
  };

  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
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

  programs.gpg = {
    enable = true;
    publicKeys = [ {
      source = ./config/gpgpubkey.txt;
      trust = 5;
    } ];
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
    extraLuaConfig = lib.fileContents config/vim/init.lua;
    vimAlias = true;
    vimdiffAlias = true;
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
      coc-cmake
      coc-clangd
      vim-tmux-navigator # allow ctrl-hjkl across panes
      vim-polyglot       # syntax highlight all the things
      mini-nvim          #TODO: Still unsure how to use mini.file from this, supercede oil?
      vim-fugitive       # Git interaction
      vimwiki            # Wiki notes in vim
      fzf-vim            # file path/contents fuzzyfind
      trouble-nvim
      pkgs.unstable.vimPlugins.openingh-nvim
      {
        plugin = neo-tree-nvim;
        type = "lua";
        config = ''
          require('neo-tree').setup({
            close_if_last_window = true,
            buffers = {
              follow_current_file = {
                enabled = true,
              },
            },
            filesystem = {
              follow_current_file = {
                enabled = true,
              },
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
      nd = "nix develop"; # <-- me avoiding direnv
    };

    sessionVariables = {
      EDITOR = "nvim";
      TERMINAL = "kitty";
    };

    initExtra = ''
      PATH=/home/josh/.local/bin:$PATH

      function _update_ps1() {
        PS1="$(${pkgs.powerline-go}/bin/powerline-go -modules 'venv,ssh,cwd,perms,git,jobs,exit,root,nix-shell' -error $?)"
      }
      PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"

      set -o vi
    '';
  };
}
