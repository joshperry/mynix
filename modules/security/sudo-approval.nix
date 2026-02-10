{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.security.sudo-approval;

  socketPath = "/run/sudo-approval/socket";

  # Script that requests approval and runs command if approved
  approvalWrapper = pkgs.writeShellScriptBin "sudo-with-approval" ''
    set -e

    SOCKET_PATH="${socketPath}"
    REQUESTING_USER="''${SUDO_USER:-$(whoami)}"
    COMMAND="$*"

    if [ -z "$COMMAND" ]; then
      echo "Usage: sudo sudo-with-approval <command>" >&2
      exit 1
    fi

    # Check if socket exists
    if [ ! -S "$SOCKET_PATH" ]; then
      echo "Error: Approval daemon is not running (socket not found at $SOCKET_PATH)" >&2
      exit 1
    fi

    echo "Requesting approval to run: $COMMAND" >&2

    # Send request to daemon and wait for response
    # Use stdio with ignoreeof to keep reading after input closes
    RESPONSE=$(printf "%s\n" "$REQUESTING_USER:$COMMAND" | ${pkgs.socat}/bin/socat STDIO,ignoreeof UNIX-CONNECT:"$SOCKET_PATH" || echo "ERROR")

    if [ "$RESPONSE" = "APPROVED" ]; then
      echo "Approved! Executing command..." >&2
      exec ${pkgs.sudo}/bin/sudo "$@"
    elif [ "$RESPONSE" = "DENIED" ]; then
      echo "Request denied." >&2
      exit 1
    else
      echo "Error communicating with approval daemon (got: '$RESPONSE')" >&2
      exit 1
    fi
  '';

in {
  options.security.sudo-approval = {
    enable = mkEnableOption "sudo approval system for delegated users";

    delegatedUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users who can request sudo approval via sudo-with-approval wrapper";
    };

    socketOwner = mkOption {
      type = types.str;
      default = "root";
      description = "Owner of the socket directory (usually matches the user running the daemon)";
    };
  };

  config = mkIf cfg.enable {
    # Install the wrapper script
    environment.systemPackages = [ approvalWrapper ];

    # Configure sudo to allow delegated users to use the wrapper
    # The wrapper itself will check for approval before executing
    # Use /run/current-system/sw/bin path since that's what gets called
    security.sudo.extraRules = [
      {
        users = cfg.delegatedUsers;
        runAs = "root:root";
        commands = [
          {
            command = "/run/current-system/sw/bin/sudo-with-approval";
            options = [ "NOPASSWD" "SETENV" ];
          }
        ];
      }
    ];

    # Ensure the socket directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /run/sudo-approval 0755 ${cfg.socketOwner} ${cfg.socketOwner} -"
    ];
  };
}
