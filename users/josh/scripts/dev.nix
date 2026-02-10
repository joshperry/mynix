{ pkgs }:

let
  # Helper script to run claude as ada in a specific directory
  claude-as-ada = pkgs.writeShellScript "claude-as-ada" ''
    path="$1"
    shift
    exec sudo machinectl shell ada@ ${pkgs.bash}/bin/bash -l -c "cd '$path' && exec ${pkgs.unstable.claude-code}/bin/claude $*"
  '';
in

pkgs.writeShellScriptBin "dev" ''
  #!/usr/bin/env bash
  # This script opens a new tmux pane in the style of my preferred dev UI using
  # fzf to allow fuzzily finding the project dir I want to work in.
  #
  # I put my code under ~/dev so it lists folders 2-deep from there. There is no
  # interface the target dir has to expose, though this pairs quite well with
  # .envrc + flakes and devenv (cref: `josh.nix` programs.direnv).
  #
  # With a decent powerline config for your PS1, vim status, tmux
  # status, and i3 status below that, you get a pretty information
  # dense environment over a wide range of hierarchical contexts.
  #
  # Pane 0 is always my bootstrap pane, I use this mostly for running
  # this script but sometimes one-off commands(every window has a shell,
  # so it's rare).
  #
  # Using tmux-fzf paired with panes named by the chosen directory makes
  # navigating these contexts dynamic and quick.
  #
  # 75% claude as ada
  # ---------
  # 25% shell
  # [tmux 0> pane 1> list 2>]
  path=$1
  if [ "$#" -eq 0 ]; then
    selection=$(find ~/dev -maxdepth 2 -type d -not -path '*/.*' -printf '%P\n' | fzf)
    [[ -z "$selection" ]] && exit 1
    path=~/dev/"$selection"
  fi

  name=`basename $path`

  tmux new-window -c "$path" -n $name
  # Run claude as ada using helper script with interpolated paths
  tmux send-keys "${claude-as-ada} \"$path\" --dangerously-skip-permissions" C-m
  tmux split-window -v -l 25% -c "$path"
  tmux last-pane
''
