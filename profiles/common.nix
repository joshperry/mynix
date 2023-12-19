{ pkgs, ... }: {

  # Enable flakes and the future of `$ nix`
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    at-spi2-core
    cifs-utils
    ethtool
    gdb
    glances
    gnupg
    htop
    jq
    lshw
    libnotify
    lzop
    nvd
    pciutils
    pv
    wget
    unzip
    yq
    zip
  ];
}
