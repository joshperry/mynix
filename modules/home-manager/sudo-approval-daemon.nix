{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sudo-approval-daemon;

  socketPath = "/run/sudo-approval/socket";

  # Handler script that processes each approval request
  approvalHandler = pkgs.writeShellScript "sudo-approval-handler" ''
    # Read the request from stdin (format: "user:command")
    read -r REQUEST

    USER=$(echo "$REQUEST" | cut -d: -f1)
    COMMAND=$(echo "$REQUEST" | cut -d: -f2-)

    # Escape HTML entities to prevent markup injection
    # Replace & < > with their HTML entities
    USER_ESC=$(echo "$USER" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    COMMAND_ESC=$(echo "$COMMAND" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    # Show notification with approve/deny buttons using zenity
    # Use --default-cancel to prevent accidental approval from typing
    if ${pkgs.zenity}/bin/zenity \
        --question \
        --title="Sudo Approval Request" \
        --text="User <b>$USER_ESC</b> wants to run:\n\n<tt>$COMMAND_ESC</tt>\n\nApprove?" \
        --ok-label="Approve" \
        --cancel-label="Deny" \
        --default-cancel \
        --width=500 \
        --timeout=60 \
        2>/dev/null; then
      echo "APPROVED"
    else
      echo "DENIED"
    fi
  '';

  # Daemon that handles approval requests and shows GUI notifications
  approvalDaemon = pkgs.writeShellScript "sudo-approval-daemon" ''
    set -euo pipefail

    SOCKET_PATH="${socketPath}"
    SOCKET_DIR=$(dirname "$SOCKET_PATH")

    # Create socket directory if it doesn't exist
    mkdir -p "$SOCKET_DIR"
    chmod 755 "$SOCKET_DIR"

    # Remove old socket if it exists
    rm -f "$SOCKET_PATH"

    echo "Starting sudo approval daemon on $SOCKET_PATH"

    # Start socat to listen on Unix socket
    # For each connection, fork and run the handler
    ${pkgs.socat}/bin/socat \
      UNIX-LISTEN:"$SOCKET_PATH",fork,mode=666 \
      EXEC:"${approvalHandler}"
  '';

in {
  options.services.sudo-approval-daemon = {
    enable = mkEnableOption "sudo approval daemon for approving sudo requests";
  };

  config = mkIf cfg.enable {
    systemd.user.services.sudo-approval-daemon = {
      Unit = {
        Description = "Sudo Approval Daemon";
        After = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${approvalDaemon}";
        Restart = "always";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
