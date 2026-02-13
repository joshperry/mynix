{ pkgs }:

# Thin wrapper around nuketown's portal-ada.
# All layout, project path mapping, and agent launching logic
# lives in the nuketown module now.
pkgs.writeShellScriptBin "dev" ''
  exec portal-ada "$@"
''
