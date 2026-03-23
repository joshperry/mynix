{ config, lib, pkgs, ... }:

let
  cfg = config.time;
in {
  # NixOS manages /etc/localtime declaratively and patches systemd-timedated
  # to reject timedatectl set-timezone. This means no PropertiesChanged dbus
  # signal fires on timezone changes, so GUI apps (Thunderbird, Chromium,
  # Discord) never notice.
  #
  # This activation script emits the signal directly after the etc activation
  # updates the symlink.
  system.activationScripts.timezoneNotify = lib.stringAfter [ "etc" ] ''
    ${pkgs.systemd}/bin/busctl emit \
      /org/freedesktop/timedate1 \
      org.freedesktop.DBus.Properties \
      PropertiesChanged \
      "sa{sv}as" \
      org.freedesktop.timedate1 \
      2 \
        Timezone s ${lib.escapeShellArg cfg.timeZone} \
        TimezoneFileContent s "" \
      0 \
      2>/dev/null || true
  '';
}
