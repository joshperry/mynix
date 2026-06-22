{ writeShellApplication, symlinkJoin, step-cli, step-kms-plugin, gnupg }:

# LAN certificate authority backed by a YubiKey PIV slot.
#
# The CA private key is generated on the YubiKey and never leaves the token, so
# issuing a cert always requires the PIN (and a touch, per the slot's policy).
# `lan-ca-init` bootstraps the CA once; `lan-cert` issues leaf certs against it.
let
  # GnuPG's scdaemon keeps a live pcsc connection to the card, which blocks
  # step-kms-plugin's exclusive PIV connect ("other connections outstanding").
  # Drop it before any PIV op; it respawns (via pcsc-shared) on the next gpg use.
  releaseCard = ''
    gpgconf --kill scdaemon 2>/dev/null || true
  '';

  lan-ca-init = writeShellApplication {
    name = "lan-ca-init";
    runtimeInputs = [ step-cli step-kms-plugin gnupg ];
    text = ''
      slot="''${LAN_CA_SLOT:-9c}"
      subject="''${1:-Switchy LAN Root CA}"
      out="''${LAN_CA_CRT_OUT:-./lan-ca.crt}"
      pin_policy="''${LAN_CA_PIN_POLICY:-always}"
      touch_policy="''${LAN_CA_TOUCH_POLICY:-always}"
      validity="''${LAN_CA_VALID:-87600h}"

      cat >&2 <<EOF
      lan-ca-init: bootstrap the LAN CA on YubiKey PIV slot $slot
        subject:      $subject
        pin policy:   $pin_policy
        touch policy: $touch_policy
        validity:     $validity
        cert out:     $out

      This OVERWRITES any key in PIV slot $slot and CANNOT be undone. The CA
      private key is generated on the token and never leaves it. You will be
      prompted for the PIV PIN and management key (and a touch).
      EOF

      read -rp "Type CONFIRM to proceed: " ans
      if [ "$ans" != "CONFIRM" ]; then
        echo "aborted" >&2
        exit 1
      fi

      ${releaseCard}
      step kms create \
        --kty EC --crv P256 \
        --pin-policy "$pin_policy" \
        --touch-policy "$touch_policy" \
        "yubikey:slot-id=$slot"

      step certificate create "$subject" "$out" \
        --profile root-ca \
        --kms "yubikey:" \
        --key "yubikey:slot-id=$slot" \
        --not-after "$validity" \
        --force

      echo "lan-ca-init: CA cert written to $out" >&2
      echo "  next: commit $out into mynix and add it to security.pki.certificateFiles" >&2
    '';
  };

  lan-cert = writeShellApplication {
    name = "lan-cert";
    runtimeInputs = [ step-cli step-kms-plugin gnupg ];
    text = ''
      host="''${1:-}"
      if [ -z "$host" ]; then
        echo "usage: lan-cert <hostname> [extra-san ...]" >&2
        echo "  signs a leaf cert with the YubiKey-PIV LAN CA (PIN + touch)" >&2
        exit 1
      fi
      shift

      ca_crt="''${LAN_CA_CRT:-./lan-ca.crt}"
      slot="''${LAN_CA_SLOT:-9c}"
      # 3y default: clears the Venus GX start-flashmq 1y checkend regen guard.
      valid="''${LAN_CERT_VALID:-26280h}"
      outdir="''${LAN_CERT_OUTDIR:-.}"

      if [ ! -f "$ca_crt" ]; then
        echo "lan-cert: CA cert not found at $ca_crt (set LAN_CA_CRT)" >&2
        exit 1
      fi

      sans=( --san "$host" )
      for s in "$@"; do
        sans+=( --san "$s" )
      done

      ${releaseCard}
      step certificate create "$host" \
        "$outdir/$host.crt" "$outdir/$host.key" \
        --ca "$ca_crt" \
        --ca-kms "yubikey:" \
        --ca-key "yubikey:slot-id=$slot" \
        "''${sans[@]}" \
        --not-after "$valid" \
        --bundle --no-password --insecure --force

      echo "lan-cert: wrote $outdir/$host.crt (+chain) and $outdir/$host.key" >&2
    '';
  };
in
symlinkJoin {
  name = "lan-ca";
  paths = [ lan-cert lan-ca-init ];
}
