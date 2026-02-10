{ pkgs, lib, ... }: {

  home.packages = with pkgs; [
    bat
    fzf
    gitmux
    imagemagick
    powerline
    powerline-go
    silver-searcher
  ];

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

  home.file.".config/powerline/themes/tmux/default.json" = {
    source = ./config/powerline/tmux/default.json;
  };

  programs.neovim = { # the power of lua beckons
    enable = true;
    extraConfig = lib.fileContents ./config/vim/vimrc;
    extraLuaConfig = lib.fileContents ./config/vim/init.lua;
    vimAlias = true;
    vimdiffAlias = true;
    coc ={ # universal lsp client
      enable = true;
      settings = {
        "suggest.noselect" = true;
        "suggest.enablePreview" = true;
        "suggest.enablePreselect" = true;
        "suggest.disableKind" = true;
        languageserver = {
          nix = { # nix language server
            command = lib.getExe pkgs.nil;
            filetypes = ["nix"];
            rootPatterns = ["flake.nix"];
          };

          beancount = {
            command = lib.getExe pkgs.beancount-language-server;
            args = [ "--stdio" ];
            filetypes = [ "beancount" ];
            rootPatterns = [ ".git" ];
            settings = {
              journal_file = "main.beancount";
              formatting = {
                prefix_width = 30;
                num_width = 10;
                currency_column = 60;
                account_amount_spacing = 2;
                number_currency_spacing = 1;
              };
            };
          };

          svelte = {
            command = lib.getExe pkgs.svelte-language-server;
            args = [ "--stdio" ];
            filetypes = ["svelte"];
            rootPatterns = ["package.json"];
          };
        };
      };
    };

    plugins = with pkgs.vimPlugins; [
      { # Lets us bind ViM config specializations for direnv projects,
        # including plugin installation like LSPs.
        plugin = pkgs.mynix.dev.direnv-nvim;
        type="lua";
        config = # lua
        ''
          vim.g.coc_start_at_startup = 0
          require('direnv-nvim').setup({
            async = true,
            on_direnv_finished = function ()
                -- Facilitate async project-specific vim tooling installed by nix-direnv
                -- by bindings to things installed by it (like LSPs) in this function.
                vim.cmd('CocStart')
            end
          })
        '';
      }
      nvim-web-devicons
      gruvbox      # theme
      coc-eslint   # CoC lsps
      coc-cmake
      coc-html
      coc-go
      coc-tsserver
      coc-yaml
      coc-rust-analyzer
      coc-cmake
      coc-clangd
      vim-tmux-navigator # allow ctrl-hjkl across vim and tmux internal panes
      mini-nvim          #TODO: Still unsure how to use mini.file from this, supercede oil?
      vim-fugitive       # A dash of tpope Git interaction goodness cref vintage:
                         # http://vimcasts.org/episodes/fugitive-vim---a-complement-to-command-line-git/
      vimwiki            # Wiki notes in vim
      fzf-vim            # file path/contents fuzzyfind
      trouble-nvim       # LSP UI
      pkgs.unstable.vimPlugins.openingh-nvim  # UI exposing "navigate to the current cursor location in
                                              # the {github|gitlab|bitbucket}.com web code editor" functionality
      { # Treesitter grammar parser and plugins (should find a way to pull plugins in at the project-level as well)
        plugin = (nvim-treesitter.withPlugins (p: [
          # Organized by OSI-ish layer order; user this end
          p.svelte
          p.css
          p.scss
          p.html
          p.beancount
          p.typescript
          p.javascript
          p.nix
          p.bash
        ]));
        type = "lua";
        config = #lua
        ''
          require('nvim-treesitter.configs').setup({
            highlight = { enable = true }, incremental_selection = { enable = true },
            indent = { enable = true },
          })
          -- Use treesitter for folding
          vim.wo.foldmethod = 'expr'
          vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
          -- default folds to open
          vim.opt.foldenable = false 
        '';
      }
      { # Left side file/project browser, originally targeted at cref: `scripts/dev.sh`
        plugin = neo-tree-nvim;
        type = "lua";
        config = #lua
        ''
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
              window = {
                mappings = {
                  ["o"] = "system_open",
                },
              },
            },
            commands = {
              system_open = function(state)
                local node = state.tree:get_node()
                local path = node:get_id()
                -- Linux: open file in default application
                vim.fn.jobstart({ "xdg-open", path }, { detach = true })
              end,
            },
          })
        '';
      }
      { # git gutter and interaction
        plugin = gitsigns-nvim;
        type = "lua";
        config = "require('gitsigns').setup()";
      }
      { #powerline-alike
        plugin = lualine-nvim;
        type = "lua";
        config = "require('lualine').setup()";
      }
      { # netrw replacement
        plugin = oil-nvim;
        type = "lua";
        config = #lua
        ''
          require('oil').setup({
          });
        '';
      }
      #{
      #  plugin = litnix-nvim;
      #  type = "lua";
      #  config = lua
      #  ''
      #    require('litnix').setup({
      #    });
      #  '';
      #}
    ];
  };

  programs.direnv = { # <-- me succumbing to direnv
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
      config = {
        # Wall of text is unhelpful, never read it close enough to "audit"
        global.hide_env_diff = true;
      };
  };

  programs.bash = { # This is the most sane way to configure bash for login shells I've ever experienced...
                    # my arch+zsh-weilding friend once asking this question:
                    # https://unix.stackexchange.com/questions/45684/what-is-the-difference-between-profile-and-bash-profile
    enable = true;

    shellAliases = {
      ll = "ls --color=auto";
      cdf = "cd $(find . -maxdepth 2 -type d -print | fzf)"; # Don't use this much with `scripts/dev.sh` alias
      nd = "nix develop"; # <-- me avoiding direnv
      tdie = "tmux killw";
    };

    sessionVariables = {
      EDITOR = "nvim";    
    };

    initExtra = #bash
    ''
      PATH=$HOME/.local/bin:$PATH

      function _update_ps1() {
        PS1="$(${pkgs.powerline-go}/bin/powerline-go -modules 'venv,ssh,cwd,perms,git,jobs,exit,root,nix-shell' -error $?)"
      }
      PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"

      set -o vi
    '';
  };
}
