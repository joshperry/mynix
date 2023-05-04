{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    at-spi2-core
    cifs-utils
    ethtool
    gdb
    glances
    gnupg
    htop
    lshw
    pciutils
    wget
    vlc
    unzip
    zip

    # Build Vim with X11 support
    (vim_configurable.overrideAttrs (old: {
      # Make the X Toolkit Intrinsics library (libXt) available during the build
      # so that Vim will compile itself with clipboard support.
      buildInputs = old.buildInputs ++ [ xorg.libXt ];
      python = python3;
    }))
  ];
}
