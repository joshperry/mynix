{ pkgs, config, lib, ... }:
{
  system.stateVersion = "24.11";

  environment.systemPackages = with pkgs; [
    irssi
  ];

  users.users.josh = {
    uid = 1000;
    group = "josh";
    initialHashedPassword = "$6$rounds=3000000$plps8mAYoxl.ngM7$UICj9iFn3SvWEBmD6Zsv0pWu8fru2jGNqvXazc7BjM9CJJxCna.du8yytejQeAL9yjQ.943AXyv8fjgSxOX.4.";
    isNormalUser = true;
    extraGroups = [
      "wheel"     # Enable 'sudo' for the user.
      "plugdev"   # Access to usb devices
      "dialout"   # Access to serials ports
    ];
  };

  users.groups.josh = {
   gid = 1000;
  };
}
