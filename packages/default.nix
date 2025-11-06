{ pkgs }: {
  mynix = {
  mynix = { #def.mynix
    drata = pkgs.callPackage ./tools/security/drata.nix {};
    ansel = pkgs.callPackage ./graphics/ansel.nix {};
    cura = pkgs.callPackage ./applications/misc/cura.nix {};
    HELI-X = pkgs.callPackage ./games/HELI-X.nix {};
    HELI-X11 = pkgs.callPackage ./games/HELI-X11.nix {};
    rotorflight-blackbox = pkgs.callPackage ./applications/misc/rotorflight-blackbox.nix {};
    rotorflight-configurator = pkgs.callPackage ./applications/misc/rotorflight-configurator.nix {};
    stm-dfu-udev-rules = pkgs.callPackage ./hardware/stm-dfu-udev-rules.nix {};
    itunes-backup-explorer = pkgs.callPackage ./tools/itunes-backup-explorer.nix {};

    dev = {
      direnv-nvim = pkgs.callPackage ./dev/direnv-nvim.nix {inherit buildVimPlugin;};
    };

    # xss-lock branch that calls logind's SetLockedHint
    xss-lock-hinted = pkgs.xss-lock.overrideAttrs (_: {
      src = pkgs.fetchFromGitHub {
        owner = "xdbob";
        repo = "xss-lock";
        # locked_hint branch https://github.com/xdbob/xss-lock/compare/locked_hint
        rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
        sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
      };
    });

    i3lock-color = pkgs.i3lock-color.overrideAttrs (prev: {
      # fork with gif support
      version = "7d337d9";
      src = pkgs.fetchFromGitHub {
        owner = "PandorasFox";
        repo = "i3lock-color";
        rev = "7d337d9133853109d7443a0150ccd26a6b1c02da";
        sha256 = "sha256-arIfZthTJ27MBmTbX0BjQ341nHrsyyFef/Wqx5kMnxI=";
      };

      buildInputs = prev.buildInputs ++ [
        pkgs.giflib
      ];
    });
  };
}
