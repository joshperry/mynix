{ writeShellApplication
, writeText
, bash
, bubblewrap
, cacert
, fontconfig
, terminus_font
, inconsolata
, dejavu_fonts
, noto-fonts
, noto-fonts-cjk-sans
, font-awesome
, tor
, librewolf
}:

let
  fontDirs = [
    terminus_font
    inconsolata
    dejavu_fonts
    noto-fonts
    noto-fonts-cjk-sans
    font-awesome
  ];

  fontsConf = writeText "fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      ${builtins.concatStringsSep "\n  " (map (d: "<dir>${d}</dir>") fontDirs)}

      <include>${fontconfig.out}/etc/fonts/conf.d</include>

      <alias binding="same">
        <family>sans-serif</family>
        <prefer><family>DejaVu Sans</family><family>Noto Sans</family></prefer>
      </alias>
      <alias binding="same">
        <family>serif</family>
        <prefer><family>DejaVu Serif</family><family>Noto Serif</family></prefer>
      </alias>
      <alias binding="same">
        <family>monospace</family>
        <prefer><family>Inconsolata</family><family>DejaVu Sans Mono</family></prefer>
      </alias>
    </fontconfig>
  '';

  browserConfig = writeText "user.js" ''
    user_pref("network.proxy.socks", "localhost");
    user_pref("network.proxy.socks_port", 9050);
    user_pref("network.proxy.type", 1);
  '';
in
writeShellApplication {
  name = "tor-librewolf";

  runtimeInputs = [ bubblewrap ];

  text = ''
    bwrap \
      --ro-bind /nix/store /nix/store \
      --ro-bind ${cacert.p11kit}/etc/ssl/trust-source /etc/ssl/trust-source \
      --proc /proc \
      --dev /dev \
      --tmpfs /tmp \
      --ro-bind ${fontsConf} /tmp/fonts.conf \
      --ro-bind "$HOME/.Xauthority" /tmp/.Xauthority \
      --ro-bind /tmp/.X11-unix /tmp/.X11-unix \
      --tmpfs /home/user \
      --tmpfs /home/user/.librewolf-profile \
      --ro-bind ${browserConfig} /home/user/.librewolf-profile/user.js \
      --unshare-all --share-net \
      --die-with-parent --new-session \
      --setenv HOME /home/user \
      --setenv DISPLAY "$DISPLAY" \
      --setenv XAUTHORITY /tmp/.Xauthority \
      --setenv FONTCONFIG_FILE /tmp/fonts.conf \
      ${bash}/bin/sh -c '${tor}/bin/tor & exec ${librewolf}/bin/librewolf --profile /home/user/.librewolf-profile --no-remote'
  '';

  meta.description = "Librewolf in a bubblewrap sandbox, traffic routed through a private tor SOCKS instance";
}
