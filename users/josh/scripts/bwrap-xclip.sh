# xclip — clipboard proxy shim
# Shadows the real xclip inside the sandbox.
# Handles the flag combos neovim's clipboard provider actually uses.
socket="/project/.dev/clipboard.sock"

case "$*" in
  *"-o"*)
    echo paste | socat - UNIX-CONNECT:"$socket"
    ;;
  *)
    (echo copy; cat) | socat - UNIX-CONNECT:"$socket"
    ;;
esac
