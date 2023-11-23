{ pkgs }: {
  drata = pkgs.callPackage ./tools/security/drata.nix {};
  ansel = pkgs.callPackage ./graphics/ansel.nix {};
}
