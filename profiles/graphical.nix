{ ... }: {
  imports = [
    ./common.nix
  ];

  security.pam.services.i3lock.enable = true;
}
