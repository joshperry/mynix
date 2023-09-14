#!/usr/bin/env bash
path=$1
if [ "$#" -eq 0 ]; then
  selection=$(find ~/dev -maxdepth 2 -type d -not -path '*/.*' -printf '%P\n' | fzf)
  [[ -z "$selection" ]] && exit 1
  path=~/dev/"$selection"
fi

name=`basename $path`

tmux new-window -c "$path" -n $name
tmux send-keys 'vim +NERDTree' C-m
tmux split-window -v -l 25% -c "$path"
tmux last-pane
