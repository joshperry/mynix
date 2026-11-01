{ config, pkgs, ... }:
# Off-box notification as kago@6bit.com via liver's Prosody:
#
#   kago-notify [-p low|default|high] [-u url] <subject> [body]   (body "-": stdin)
#
# Publishes to the `kago` topic on notify.6bit.com (pubsub-push: delivered to
# josh's phone through Conversations, store-and-forward; high pops up, url
# opens on tap). If the publish fails, falls back to a direct XMPP message
# to josh, so a broken topic path still gets noticed. Exits non-zero only if
# both fail.
let
  kago-notify = pkgs.writeShellApplication {
    name = "kago-notify";
    runtimeInputs = [ pkgs.pubsub-publish pkgs.go-sendxmpp pkgs.coreutils ];
    text = ''
      priority=default url=
      while getopts p:u: opt; do
        case $opt in
          p) priority=$OPTARG ;;
          u) url=$OPTARG ;;
          *) echo "usage: kago-notify [-p low|default|high] [-u url] subject [body|-]" >&2; exit 2 ;;
        esac
      done
      shift $((OPTIND - 1))
      subject=$1
      body=''${2:-}
      if [ "$body" = - ]; then body=$(cat); fi

      if pubsub-publish --jid kago@6bit.com \
          --password-file ${config.sops.secrets."xmpp/m2m_password".path} \
          --service notify.6bit.com --topic kago --priority "$priority" \
          ''${url:+--url "$url"} "$subject" "$body"; then
        exit 0
      fi

      # go-sendxmpp keeps a client id under $HOME; units run without one.
      export HOME=/var/lib/kago-notify XDG_CACHE_HOME=/var/lib/kago-notify/.cache
      mkdir -p "$XDG_CACHE_HOME"
      # Prosody authenticates against Dovecot, so it only offers PLAIN (after
      # STARTTLS). FAST tokens off: nothing to keep between runs.
      printf 'kago: %s (topic publish failed)\n%s\n' "$subject" "$body" \
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
      ${kago-notify}/bin/kago-notify -p low "up" "booted $(${pkgs.procps}/bin/uptime -s), $(grep -c '\[UUU\]' /proc/mdstat)/3 md arrays clean"
    '';
  };

  # OnFailure= target for jobs worth a message but not the beeping alarm.
  systemd.services."kago-notify-failure@" = {
    description = "Tell josh %i failed";
    serviceConfig.Type = "oneshot";
    script = ''
      journalctl -u "$1" -n 15 --no-pager -o cat | ${kago-notify}/bin/kago-notify -u https://kago.local:9090/ "$1 failed" -
    '';
    scriptArgs = "%i";
  };
  systemd.services.restic-backups-bu-offsite.onFailure = [ "kago-notify-failure@%n.service" ];

  # Used by the alarm timer (beep.nix) to send one message per raised alarm.
  _module.args.kago-notify = kago-notify;
}
