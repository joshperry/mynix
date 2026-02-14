{ pkgs }: 
let
  patchDesktop = pkg: appName: from: to: pkgs.lib.hiPrio (
    pkgs.runCommand "$patched-desktop-entry-for-${appName}" {} ''
      ${pkgs.coreutils}/bin/mkdir -p $out/share/applications
      ${pkgs.gnused}/bin/sed 's#${from}#${to}#g' < ${pkg}/share/applications/${appName}.desktop > $out/share/applications/${appName}.desktop
    '');
  inherit (pkgs.vimUtils.override { inherit (pkgs) vim; }) buildVimPlugin;
  inherit (pkgs.neovimUtils) buildNeovimPlugin;
in
{
  mynix = { #def.mynix
    drata = pkgs.callPackage ./tools/security/drata.nix {};
    ansel = pkgs.callPackage ./graphics/ansel.nix {};
    blhelisuite32 = pkgs.callPackage ./hardware/blhelisuite32.nix{};
    cura = pkgs.callPackage ./applications/misc/cura.nix {};
    HELI-X = pkgs.callPackage ./games/HELI-X.nix {};
    HELI-X11 = pkgs.callPackage ./games/HELI-X11.nix {};
    rotorflight-blackbox = pkgs.callPackage ./applications/misc/rotorflight-blackbox.nix {};
    rotorflight-configurator = pkgs.callPackage ./applications/misc/rotorflight-configurator.nix {};
    inav-configurator = pkgs.callPackage ./applications/misc/inav-configurator.nix {};
    stm-dfu-udev-rules = pkgs.callPackage ./hardware/stm-dfu-udev-rules.nix {};
    cc-prism = pkgs.callPackage ./tools/cc-prism.nix {};
    itunes-backup-explorer = pkgs.callPackage ./tools/itunes-backup-explorer.nix {};

    dev = {
      direnv-nvim = pkgs.callPackage ./dev/direnv-nvim.nix {inherit buildVimPlugin;};
    };

    NvidiaOffloadApp = pkg: desktopName: patchDesktop pkg desktopName "^Exec=" "Exec=nvidia-offload ";

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

  gnuradio = pkgs.gnuradio.override {
    extraPackages = grPkgs: [ grPkgs.limesdr ];
  } // {
    pkgs = pkgs.gnuradio.pkgs.overrideScope (grFinal: grPrev: {
      limesdr = grPrev.callPackage ./gr-limesdr.nix { };
    });
  };
}
