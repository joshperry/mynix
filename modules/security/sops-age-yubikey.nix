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

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "sops-age";
        RuntimeDirectoryMode = "0700";

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

        printf '\033[2J\033[H'

        echo ""
        echo "=== Decrypting sops age key — touch YubiKey when it flashes ==="
        echo ""

        gpg --decrypt \
          --output "${cfg.keyFile}" \
          "${cfg.encryptedKeyFile}"

        chmod 0400 "${cfg.keyFile}"

        echo "Age key decrypted."
      '';
    };
  };
}
