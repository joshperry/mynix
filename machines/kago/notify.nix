{ config, pkgs, ... }:
# Off-box notification: XMPP messages from kago@6bit.com to josh@6bit.com via
# liver's Prosody. `kago-notify <subject> [body]`, or the body on stdin with
# `-`. Exits non-zero if the message wasn't sent.
let
  kago-notify = pkgs.writeShellApplication {
    name = "kago-notify";
    runtimeInputs = [ pkgs.go-sendxmpp pkgs.coreutils ];
    text = ''
      subject=$1
      body=''${2:-}
      if [ "$body" = - ]; then body=$(cat); fi
      # go-sendxmpp keeps a client id under $HOME; units run without one.
      export HOME=/var/lib/kago-notify XDG_CACHE_HOME=/var/lib/kago-notify/.cache
      mkdir -p "$XDG_CACHE_HOME"
      # Prosody authenticates against Dovecot, so it only offers PLAIN (after
      # STARTTLS). FAST tokens off: nothing to keep between runs.
      printf 'kago: %s\n%s\n' "$subject" "$body" \
        | go-sendxmpp -f ${config.sops.templates.kago-sendxmpprc.path} \
            --allow-plain --fast-off --suppress-root-warning --timeout 30 \
            josh@6bit.com
    '';
  };
in
{
  sops.secrets."xmpp/m2m_password" = { };
  sops.templates.kago-sendxmpprc.content = ''
    username: kago@6bit.com
    password: ${config.sops.placeholder."xmpp/m2m_password"}
  '';

  environment.systemPackages = [ kago-notify ];

  # Booted (and the first deploy of this): proves the path end to end.
  systemd.services.kago-notify-boot = {
    description = "Tell josh kago is up";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "1min";
    };
    script = ''
      ${kago-notify}/bin/kago-notify "up" "booted $(${pkgs.procps}/bin/uptime -s), $(grep -c '\[UUU\]' /proc/mdstat)/3 md arrays clean"
    '';
  };

  # OnFailure= target for jobs worth a message but not the beeping alarm.
  systemd.services."kago-notify-failure@" = {
    description = "Tell josh %i failed";
    serviceConfig.Type = "oneshot";
    script = ''
      journalctl -u "$1" -n 15 --no-pager -o cat | ${kago-notify}/bin/kago-notify "$1 failed" -
    '';
    scriptArgs = "%i";
  };
  systemd.services.restic-backups-bu-offsite.onFailure = [ "kago-notify-failure@%n.service" ];

  # Used by the alarm timer (beep.nix) to send one message per raised alarm.
  _module.args.kago-notify = kago-notify;
}
