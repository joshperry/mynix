{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.security.sops-age-yubikey;
in {
  options.security.sops-age-yubikey = {
    enable = mkEnableOption "YubiKey-based GPG decryption of sops age key at boot";

    encryptedKeyFile = mkOption {
      type = types.path;
      description = "Path to the GPG-encrypted age key file";
    };

    keyFile = mkOption {
      type = types.str;
      default = "/run/sops-age/keys.txt";
      description = "Path where the decrypted age key will be written";
    };

    gpgPublicKey = mkOption {
      type = types.path;
      description = "Path to the GPG public key file (used to set up a temporary keyring with YubiKey stubs)";
    };

    tty = mkOption {
      type = types.str;
      default = "/dev/tty1";
      description = "TTY device for pinentry-curses prompts";
    };

    pinRetries = mkOption {
      type = types.int;
      default = 3;
      description = "Number of PIN entry attempts before giving up";
    };
  };

  config = mkIf cfg.enable {
    # Use systemd-based sops activation so we can order our service before it
    sops.useSystemdActivation = true;

    # pcscd is required for smartcard/YubiKey access
    services.pcscd.enable = true;

    systemd.services.sops-age-yubikey = {
      description = "Decrypt sops age key via YubiKey GPG";
      wantedBy = [ "sysinit.target" ];
      before = [ "sops-install-secrets.service" "display-manager.service" ];
      after = [ "pcscd.socket" "systemd-tmpfiles-setup.service" ];
      wants = [ "pcscd.socket" ];
      requires = [ "pcscd.socket" ];

      unitConfig.DefaultDependencies = false;
      # Boot only: a restart on switch would ask for the PIN on tty1 mid-session.
      restartIfChanged = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        # Bind to dedicated TTY for pinentry-curses
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = cfg.tty;
        TTYReset = true;
        TTYVHangup = true;

        Environment = "TERM=linux";
      };

      path = [ pkgs.gnupg pkgs.pinentry-curses pkgs.kbd ];

      script = ''
        GNUPGHOME=$(mktemp -d)
        export GNUPGHOME
        export GPG_TTY="${cfg.tty}"

        cleanup() {
          # Re-enable systemd status output and kernel messages
          kill -s RTMIN+20 1 2>/dev/null || true
          setterm --msg on 2>/dev/null || true
          rm -rf "$GNUPGHOME"
        }
        trap cleanup EXIT

        # Not a RuntimeDirectory: that would reset an existing directory
        # (nuketown's tmpfiles rule makes it writable by the approval broker)
        # to root 0700 for as long as this unit stays active.
        keydir=$(dirname "${cfg.keyFile}")
        [ -d "$keydir" ] || mkdir -p -m 0700 "$keydir"

        # Configure pinentry for this session
        mkdir -p "$GNUPGHOME"
        echo "pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses" > "$GNUPGHOME/gpg-agent.conf"

        # Build a temporary keyring: import public key, then learn card stubs
        gpg --batch --import "${cfg.gpgPublicKey}"

        # Wait for YubiKey to become available via pcscd
        echo "Waiting for YubiKey smartcard..."
        for i in $(seq 1 30); do
          if gpg --batch --card-status > /dev/null 2>&1; then
            echo "YubiKey detected."
            break
          fi
          if [ "$i" -eq 30 ]; then
            echo "ERROR: YubiKey not detected after 30 attempts" >&2
            exit 1
          fi
          sleep 1
        done

        gpg-connect-agent reloadagent /bye > /dev/null 2>&1 || true

        # Suppress all console output while pinentry is active:
        # - systemd status (writes to /dev/console = /dev/tty0 = foreground VT)
        # - kernel printk (routed to foreground VT via /dev/tty0)
        # Without this, boot progress text overwrites the pinentry prompt.
        kill -s RTMIN+21 1   # tell systemd PID 1 to stop printing status
        setterm --msg off 2>/dev/null || true

        for attempt in $(seq 1 ${toString cfg.pinRetries}); do
          printf '\033[2J\033[H'
          echo ""
          if [ "$attempt" -gt 1 ]; then
            echo "*** Wrong PIN — attempt $attempt of ${toString cfg.pinRetries} ***"
            echo ""
          fi
          echo "=== Decrypting sops age key — touch YubiKey when it flashes ==="
          echo ""

          if gpg --decrypt \
               --output "${cfg.keyFile}" \
               "${cfg.encryptedKeyFile}"; then
            chmod 0400 "${cfg.keyFile}"
            echo "Age key decrypted."
            exit 0
          fi

          rm -f "${cfg.keyFile}"
          # Flush the cached bad PIN so gpg-agent prompts again
          gpg-connect-agent reloadagent /bye > /dev/null 2>&1 || true
        done

        echo "ERROR: Failed to decrypt age key after ${toString cfg.pinRetries} attempts" >&2
        exit 1
      '';
    };

    # The decrypted key is only needed while sops-install-secrets runs (at
    # boot, and on a switch that decrypts it again); don't leave it in /run.
    systemd.services.sops-age-yubikey-wipe = {
      description = "Remove the decrypted sops age key";
      wantedBy = [ "sops-install-secrets.service" ];
      after = [ "sops-install-secrets.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = ''
        rm -f "${cfg.keyFile}"
      '';
    };
  };
}
