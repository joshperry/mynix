{ pkgs, lib, ... }: {
  home.username = "ada";
  home.homeDirectory = lib.mkForce "/agents/ada";
  home.stateVersion = "25.11";

  # Ensure ada's home-manager profile bin is early in PATH so sudo wrapper takes precedence
  home.sessionVariables = {
    PATH = "/etc/profiles/per-user/ada/bin:$PATH";
  };

  home.packages = with pkgs; [
    git
    ripgrep
    fd
    jq
    curl
    tree

    # Wrapper script that overrides sudo to use approval system
    # Handles sudo flags like -u, -g, etc. by passing them to sudo, not sudo-with-approval
    (pkgs.writeShellScriptBin "sudo" ''
      # Parse sudo flags
      flags=()
      while [[ $# -gt 0 ]]; do
        case $1 in
          -u|-g|-C|-D|-p|-r|-t|-T|-U)
            # Flags that take an argument
            flags+=("$1" "$2")
            shift 2
            ;;
          -A|-b|-E|-H|-i|-k|-K|-l|-n|-P|-S|-s|-V|-v)
            # Flags that don't take an argument
            flags+=("$1")
            shift
            ;;
          --)
            # End of flags marker
            shift
            break
            ;;
          -*)
            # Unknown flag, pass it through
            flags+=("$1")
            shift
            ;;
          *)
            # First non-flag argument, this is the command
            break
            ;;
        esac
      done

      # Now $@ contains only the command and its arguments
      # Pass flags to sudo-with-approval, which will execute sudo with them after approval
      exec /run/wrappers/bin/sudo sudo-with-approval "''${flags[@]}" "$@"
    '')
  ];

  ###
  # Claude Code
  programs.claude-code = {
    enable = true;
    package = pkgs.unstable.claude-code;

    settings = {
      permissions = {
        # Ada uses an approval-gated sudo wrapper, so privileged operations
        # go through josh's GUI approval. Default mode is still ask-based
        # for safety.
        defaultMode = "bypassPermissions";
        additionalDirectories = [
          "/home/josh/dev"
        ];
      };
    };

    agents = {
      ada = ''
        ---
        name: ada
        description: Ada's environment and identity on signi
        ---

        You are Ada, a coding agent running on the NixOS machine "signi". You operate
        as the user `ada` (uid 1100) with home directory /agents/ada. You collaborate
        with josh, who owns and administers this machine.

        ## Environment

        - **OS**: NixOS 25.11 with flake-based configuration
        - **Machine**: signi — josh's primary workstation (Intel + NVIDIA Optimus)
        - **Home**: /agents/ada — ephemeral, may be wiped on reboot
        - **Persistent storage**: only /persist and /nix survive reboots
        - **Shell**: Non-interactive bash sessions. No TTY. No interactive prompts.
        - **Projects**: You have read/write access to /home/josh/dev via filesystem ACL

        ## Sudo

        Your sudo command routes through an approval daemon. Josh gets a GUI popup
        to approve or deny each invocation. Keep this in mind:
        - Use sudo sparingly — each call interrupts josh with a dialog
        - Batch privileged operations into a single sudo call when possible
        - If sudo hangs, josh may not be at his desk — don't retry in a loop

        ## Working Style

        - Read the project's CLAUDE.md before starting work — it has project-specific
          workflow instructions
        - Prefer editing existing files over creating new ones
        - You cannot use interactive commands (no TTY) — avoid anything that prompts
          for input, uses a pager, or expects a terminal
      '';
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls --color=auto";
    };
  };

  programs.git = {
    enable = true;
    userName = "Ada";
    userEmail = "ada@signi.local";
    extraConfig = {
      init.defaultBranch = "master";
      pull.rebase = true;
      safe.directory = "*";
    };
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    defaultEditor = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
}
