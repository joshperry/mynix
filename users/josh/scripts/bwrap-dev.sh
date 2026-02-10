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
# 75% vim with file tree expanded 
# ---------
# 25% shell
# [tmux 0> pane 1> list 2>]
#
# Usage:
#   dev [path]              — open tmux layout for project
#   dev --sandbox <path>    — enter sandboxed shell (used internally by tmux panes)

# ── Sandbox mode: bubblewrap into a project dir ─────────────────
if [[ "${1:-}" == "--sandbox" ]]; then
  path="$(realpath "$2")"
  shift 2

  mkdir -p "$path/.dev"/{data,state,cache}

  args=(
    --die-with-parent

    --ro-bind /nix/store /nix/store
    --ro-bind /nix/var /nix/var

    --proc /proc
    --dev /dev
    --tmpfs /tmp

    --ro-bind /etc /etc
    --ro-bind /run /run
  )

  # Paths that may not exist on NixOS
  for p in /usr /bin /lib /lib64; do
    [[ -e "$p" ]] && args+=(--ro-bind "$p" "$p")
  done

  args+=(
    --tmpfs "$HOME"
    --ro-bind "$HOME/.config" "$HOME/.config"
  )

  # Nix user paths that may not exist yet
  for p in "$HOME/.local/state/nix" "$HOME/.nix-defexpr" "$HOME/.nix-profile"; do
    [[ -e "$p" ]] && args+=(--ro-bind "$p" "$p")
  done

  # Home-manager dotfiles — symlinks into the nix store
  for f in "$HOME"/.*; do
    if [[ -L "$f" ]] && [[ "$(readlink "$f")" == /nix/store/* ]]; then
      args+=(--ro-bind "$f" "$f")
    fi
  done

  args+=(
    --bind "$path" "$path"
    --bind "$path/.dev/data" "$HOME/.local/share"
    --bind "$path/.dev/state" "$HOME/.local/state"
    --bind "$path/.dev/cache" "$HOME/.cache"

    --setenv XDG_DATA_HOME "$HOME/.local/share"
    --setenv XDG_STATE_HOME "$HOME/.local/state"
    --setenv XDG_CACHE_HOME "$HOME/.cache"
    --setenv HISTFILE "$HOME/.local/state/bash_history"
    --setenv NODE_REPL_HISTORY "$HOME/.local/state/node_history"
    --setenv NPM_CONFIG_CACHE "$HOME/.cache/npm"
    --setenv CARGO_HOME "$HOME/.local/share/cargo"
    --setenv GOPATH "$HOME/.local/share/go"
    --setenv CLAUDE_CONFIG_DIR "$HOME/.local/share/claude"
    --setenv PATH "$XCLIP_SHIM_BIN:${PATH:-}"

    --chdir "$path"
  )


  if [[ $# -gt 0 ]]; then
    exec bwrap "${args[@]}" "$@"
  else
    exec bwrap "${args[@]}" bash --login
  fi
fi

# ── Layout mode: fzf project selection + tmux window ────────────
path="${1:-}"
if [[ -z "$path" ]]; then
  selection=$(find ~/dev -maxdepth 2 -type d -not -path '*/.*' -printf '%P\n' | fzf) || exit 1
  path=~/dev/"$selection"
fi

path="$(realpath "$path")"
name="$(basename "$path")"

# ── Clipboard proxy (host side, real X11 access) ────────────────
socket="$path/.dev/clipboard.sock"
rm -f "$socket"
socat "UNIX-LISTEN:$socket,fork,mode=0600" SYSTEM:"
  read -r cmd
  if [ \"\$cmd\" = \"copy\" ]; then
    $REAL_XCLIP -sel clip
  elif [ \"\$cmd\" = \"paste\" ]; then
    $REAL_XCLIP -sel clip -o
  fi
" &
CLIPBOARD_PID=$!
trap 'kill $CLIPBOARD_PID 2>/dev/null; rm -f "'"$socket"'"' EXIT

tmux new-window -c "$path" -n "$name"
tmux send-keys "dev --sandbox '$path' nvim +Neotree\\ focus\\ toggle" C-m
tmux split-window -v -l 25% -c "$path"
tmux send-keys "dev --sandbox '$path'" C-m
tmux last-pane
