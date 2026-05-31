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
    signing = lib.mkDefault {
      key = null;
      signByDefault = true;
    };
    settings = {
      user.name = lib.mkDefault "Joshua Perry";
      user.email = lib.mkDefault "josh@6bit.com";
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

  imports = [ ./tmux.nix ];

  programs.neovim = { # the power of lua beckons
    enable = true;
    extraConfig = lib.fileContents ./config/vim/vimrc;
    initLua = lib.fileContents ./config/vim/init.lua;
    vimAlias = true;
    vimdiffAlias = true;

    withRuby = false;
    withPython3 = false;

    # Language servers on PATH so vim.lsp.enable can launch them
    extraPackages = with pkgs; [
      nil                          # nix
      beancount-language-server
      svelte-language-server
      vscode-langservers-extracted # html, css, json, eslint
      cmake-language-server
      gopls
      typescript-language-server
      yaml-language-server
      rust-analyzer
      clang-tools                  # clangd
    ];

    plugins = with pkgs.vimPlugins; [
      nvim-web-devicons
      gruvbox      # theme
      { # completion engine — replaces CoC's popup menu, talks to native LSP
        plugin = blink-cmp;
        type = "lua";
        config = #lua
        ''
          require('blink.cmp').setup({
            keymap = { preset = 'enter' },
            completion = {
              list = { selection = { preselect = false, auto_insert = true } },
              documentation = { auto_show = true },
            },
            signature = { enabled = true },
          })
        '';
      }
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
          require('nvim-treesitter').setup()
          -- The main-branch rewrite dropped nvim-treesitter.configs; highlight and
          -- indent now come from native treesitter, started per-buffer when a parser exists.
          vim.api.nvim_create_autocmd('FileType', {
            callback = function(args)
              if pcall(vim.treesitter.start, args.buf) then
                vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
              end
            end,
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
