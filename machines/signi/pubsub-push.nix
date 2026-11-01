{ config, pkgs, pubsub-publish, ... }:
# Discord → josh's phone while signi is locked (pubsub-push).
#
# Discord runs with Vencord and its PubsubPush plugin (overlay in flake.nix).
# For each notification Discord would show, the plugin runs `forwardIf` and,
# if josh's screen is locked, publishes it as signi@6bit.com to the
# `signi-discord` topic on notify.6bit.com, with a link to the message.
{
  # Owned by josh: the plugin runs inside josh's Discord.
  # New on signi: materializes only after the YubiKey unlocks the sops age
  # key (reboot, or sops-age-yubikey then sops-install-secrets at tty1).
  sops.secrets."xmpp/m2m_password".owner = "josh";

  home-manager.users.josh.xdg.configFile."pubsub-push/discord.json".text = builtins.toJSON {
    publish = [
      "${pubsub-publish}/bin/pubsub-publish"
      "--jid" "signi@6bit.com"
      "--password-file" config.sops.secrets."xmpp/m2m_password".path
      "--service" "notify.6bit.com"
      "--topic" "signi-discord"
    ];
    # session-lock runs i3lock-color while locked.
    forwardIf = [ "${pkgs.procps}/bin/pgrep" "-xu" "josh" "i3lock-color" ];
  };
}
