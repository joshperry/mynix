{ pkgs, ... }: {
  imports = [
    ./common.nix
  ];

  programs.gnupg.agent.pinentryPackage = pkgs.pinentry.gtk2;

  security.pam.services.i3lock.enable = true;
  services.upower.enable = true;
}
