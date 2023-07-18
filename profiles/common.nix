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
    nvd
    pciutils
    pv
    wget
    unzip
    zip

    # Build Vim with X11 support
    (vim_configurable.overrideAttrs (old: {
      # Make the X Toolkit Intrinsics library (libXt) available during the build
      # so that Vim will compile itself with clipboard support.
      buildInputs = old.buildInputs ++ [ xorg.libXt ];
      python = python310;
    }))
  ];
}
