{ config, pkgs, ... }:
# Discord → josh's phone while signi is locked (pubsub-push's
# homeManagerModules.discord, imported for josh in flake.nix).
#
# Discord runs with Vencord and its PubsubPush plugin. For each notification
# Discord would show, if josh's screen is locked, the plugin publishes it as
# signi@6bit.com to the `signi-discord` topic on notify.6bit.com, with a link
# to the message.
{
  # Owned by josh: the plugin runs inside josh's Discord.
  # New on signi: materializes only after the YubiKey unlocks the sops age
  # key (nuketown-switch does; or reboot).
  sops.secrets."xmpp/m2m_password".owner = "josh";

  home-manager.users.josh.programs.pubsub-push.discord = {
    enable = true;
    jid = "signi@6bit.com";
    passwordFile = config.sops.secrets."xmpp/m2m_password".path;
    service = "notify.6bit.com";
    topic = "signi-discord";
    # session-lock runs i3lock-color while locked.
    forwardIf = [ "${pkgs.procps}/bin/pgrep" "-xu" "josh" "i3lock-color" ];
  };
}
