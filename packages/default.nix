{ pkgs }: {
  mynix = {
    drata = pkgs.callPackage ./tools/security/drata.nix {};
    ansel = pkgs.callPackage ./graphics/ansel.nix {};
    cura = pkgs.callPackage ./applications/misc/cura.nix {};
    HELI-X = pkgs.callPackage ./games/HELI-X.nix {};
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
  };
}
