{ pkgs, lib, ... }: {
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    fzf
    powerline
    powerline-go
    silver-searcher
  ];

  home.file.".local/bin/dev" = {
    source = ./scripts/dev.sh;
    executable = true;
  };

  programs.git = {
    enable = true;
    signing = lib.mkDefault {
      key = null;
      signByDefault = false;
    };
    settings = {
      user.name = lib.mkDefault "Joshua Perry";
      user.email = lib.mkDefault "josh@6bit.com";
      init.defaultBranch = "master";
      pull.rebase = true;
      rebase.autostash = true;
    };
  };

  imports = [ ./tmux.nix ];

  programs.neovim = { # the power of lua beckons
    enable = true;
    extraConfig = lib.fileContents config/vim/vimrc;
    vimAlias = true;
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
      trouble-nvim
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
      nd = "nix develop"; # <-- me avoiding direnv
    };

    sessionVariables = {
      EDITOR = "nvim";
    };

    initExtra = #bash 
    ''
      PATH=/home/josh/.local/bin:$PATH

      function _update_ps1() {
        PS1="$(${pkgs.powerline-go}/bin/powerline-go -modules 'venv,ssh,host,cwd,perms,git,jobs,exit,root,nix-shell' -error $?)"
      }
      PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"

      set -o vi
    '';
  };
}
